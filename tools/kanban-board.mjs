#!/usr/bin/env node
/**
 * Set up the Kanban board of ADR-0042: a GitHub Project whose Status field has the columns Backlog,
 * Ready, In progress, In review and Done.
 *
 *     node tools/kanban-board.mjs --owner <organization> [--repo <owner/name>] [--project <number> | --title <title>] [--wip-limit <n>]
 *
 * It adopts the organization's project with the number --project names, or else the title --title names
 * (Kanban by default), or creates one. It links the project to the --repo repository, sets the Status
 * options in that order, keeping each existing item's status and any other option, and sets the project's
 * description to the work-in-progress limit (--wip-limit, 2 by default). GitHub's API sets no built-in
 * workflow, so it lists each one the board needs, says whether it is on, and ends with the line to add to
 * the Landing section of AGENTS.md.
 *
 * Creating a project and changing its Status options need GraphQL, so it runs on a maintainer's PC through
 * gh, which needs the project scope: gh auth refresh -h github.com -s project. It needs Node.js alone, the
 * release .node-version names: no packages.
 */
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

export const STATUSES = [
  { name: 'Backlog', color: 'GRAY', description: 'Filed, not yet ready' },
  { name: 'Ready', color: 'BLUE', description: 'Meets the Definition of Ready (ADR-0042)' },
  { name: 'In progress', color: 'YELLOW', description: 'Its plan snapshot is posted' },
  { name: 'In review', color: 'PURPLE', description: 'Its pull request is open' },
  { name: 'Done', color: 'GREEN', description: 'Closed by the merge' },
];

const USAGE = 'Usage: node tools/kanban-board.mjs --owner <organization> [--repo <owner/name>] [--project <number> | --title <title>] [--wip-limit <n>]';

// The built-in workflows the board needs: its name, and what to do when it is off.
const WORKFLOWS = [
  ['Item closed', 'it moves an item to Done'],
  ['Pull request merged', 'it moves an item to Done'],
  ['Item added to project', 'set it to move a new item to Backlog'],
  ['Auto-add to project', "set it to add the repository's open issues"],
];

/**
 * The Status options to send: the five STATUSES in order, each with the id of the existing option of the
 * same name (ignoring case; Backlog takes Todo's when there is no Backlog), then every other existing option.
 */
export function statusOptions(existing) {
  const used = new Set();
  const take = (name) => {
    const found = existing.find((option) => !used.has(option) && option.name.toLowerCase() === name.toLowerCase());
    if (found) used.add(found);
    return found;
  };
  const options = STATUSES.map((status) => {
    const found = take(status.name) ?? (status.name === 'Backlog' ? take('Todo') : undefined);
    return found ? { id: found.id, ...status } : { ...status };
  });
  const others = existing.filter((option) => !used.has(option));
  for (const option of others) {
    options.push({ id: option.id, name: option.name, color: option.color, description: option.description ?? '' });
  }
  return { options, kept: others.map((option) => option.name) };
}

export async function main(argv, { gh, log }) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      options: {
        owner: { type: 'string' },
        repo: { type: 'string' },
        project: { type: 'string' },
        title: { type: 'string', default: 'Kanban' },
        'wip-limit': { type: 'string', default: '2' },
        help: { type: 'boolean', default: false },
      },
    }));
  } catch (error) {
    log(error.message);
    log(USAGE);
    return 1;
  }
  if (values.help) {
    log(USAGE);
    return 0;
  }
  const wipLimit = values['wip-limit'];
  const invalid =
    !values.owner ||
    (values.repo !== undefined && !/^[^/\s]+\/[^/\s]+$/.test(values.repo)) ||
    (values.project !== undefined && !(/^\d+$/.test(values.project) && Number(values.project) > 0)) ||
    !(/^\d+$/.test(wipLimit) && Number(wipLimit) >= 1 && Number(wipLimit) <= 99);
  if (invalid) {
    log(USAGE);
    return 1;
  }
  const owner = values.owner;

  const auth = gh(['auth', 'status', '--hostname', 'github.com']);
  if (auth.code !== 0) {
    log("gh isn't signed in to github.com: run gh auth login.");
    return 1;
  }
  const scopes = `${auth.stdout}\n${auth.stderr}`.split(/\r?\n/).find((line) => line.includes('Token scopes:'));
  if (scopes !== undefined && !scopes.includes("'project'")) {
    log('The gh token has no project scope, which a GitHub Project needs. Run: gh auth refresh -h github.com -s project');
    return 0;
  }

  // Runs one GraphQL call; returns its data, or null after logging why it failed.
  const graphql = (query, variables) => {
    const result = gh(['api', 'graphql', '--input', '-'], JSON.stringify({ query, variables }));
    let answer;
    try {
      answer = JSON.parse(result.stdout);
    } catch {
      answer = undefined;
    }
    if (result.code !== 0 || answer?.errors) {
      const detail = (result.stderr ?? '').trim() || answer?.errors?.[0]?.message || (result.stdout ?? '').trim();
      log(`gh api graphql failed: ${detail}`);
      return null;
    }
    return answer?.data ?? {};
  };

  const org = graphql(
    'query($login: String!) { organization(login: $login) { id projectsV2(first: 100) { nodes { id number title url } } } }',
    { login: owner },
  );
  if (!org) return 1;
  if (!org.organization) {
    log(`gh api graphql failed: no organization ${owner}.`);
    return 1;
  }
  const projects = org.organization.projectsV2?.nodes ?? [];

  let repositoryId;
  if (values.repo !== undefined) {
    const [repoOwner, repoName] = values.repo.split('/');
    const repository = graphql(
      'query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { id } }',
      { owner: repoOwner, name: repoName },
    );
    if (!repository) return 1;
    repositoryId = repository.repository?.id;
    if (!repositoryId) {
      log(`gh api graphql failed: no repository ${values.repo}.`);
      return 1;
    }
  }

  let project;
  if (values.project !== undefined) {
    project = projects.find((candidate) => candidate.number === Number(values.project));
    if (!project) {
      log(`No project #${values.project} in ${owner}.`);
      return 1;
    }
    log(`Adopted project #${project.number}: ${project.url}`);
  } else {
    project = projects.find((candidate) => candidate.title === values.title);
    if (project) {
      log(`Adopted project #${project.number}: ${project.url}`);
    } else {
      const created = graphql(
        'mutation($ownerId: ID!, $title: String!) { createProjectV2(input: { ownerId: $ownerId, title: $title }) { projectV2 { id number title url } } }',
        { ownerId: org.organization.id, title: values.title },
      );
      if (!created) return 1;
      project = created.createProjectV2?.projectV2;
      if (!project) {
        log('gh api graphql failed: no project was created.');
        return 1;
      }
      log(`Created project #${project.number}: ${project.url}`);
    }
  }

  if (repositoryId !== undefined) {
    const linked = graphql(
      'mutation($projectId: ID!, $repositoryId: ID!) { linkProjectV2ToRepository(input: { projectId: $projectId, repositoryId: $repositoryId }) { repository { id } } }',
      { projectId: project.id, repositoryId },
    );
    if (!linked) return 1;
    log(`Linked ${values.repo}.`);
  }

  const details = graphql(
    'query($id: ID!) { node(id: $id) { ... on ProjectV2 { field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name color description } } } workflows(first: 50) { nodes { name enabled } } } } }',
    { id: project.id },
  );
  if (!details) return 1;
  const field = details.node?.field;
  if (!field?.id) {
    log('The project has no Status field.');
    return 1;
  }
  const workflows = details.node?.workflows?.nodes ?? [];

  const { options, kept } = statusOptions(field.options ?? []);
  const updated = graphql(
    'mutation($fieldId: ID!, $options: [ProjectV2SingleSelectFieldOptionInput!]!) { updateProjectV2Field(input: { fieldId: $fieldId, singleSelectOptions: $options }) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }',
    { fieldId: field.id, options },
  );
  if (!updated) return 1;
  log('Status: Backlog, Ready, In progress, In review, Done');
  if (kept.length > 0) log(`Kept the other options, so no item loses its status: ${kept.join(', ')}`);

  const text = `Kanban: Backlog, Ready, In progress, In review, Done. At most ${wipLimit} stories in progress and in review together.`;
  const described = graphql(
    'mutation($projectId: ID!, $text: String!) { updateProjectV2(input: { projectId: $projectId, shortDescription: $text }) { projectV2 { id } } }',
    { projectId: project.id, text },
  );
  if (!described) return 1;
  log(`Description: ${text}`);

  log(`GitHub's API sets no built-in workflow. Check each in ${project.url}/workflows:`);
  for (const [name, what] of WORKFLOWS) {
    const workflow = workflows.find((candidate) => candidate.name === name);
    if (workflow?.enabled) {
      log(`- ${name}: on`);
    } else {
      log(`- ${name}: ${workflow ? 'off' : 'not found'}; turn it on and ${what}`);
    }
  }
  log(`Add this line to the Landing section of AGENTS.md: - board: ${owner}/${project.number}`);
  return 0;
}

function gh(args, input) {
  const result = spawnSync('gh', args, { input, encoding: 'utf8' });
  return {
    code: result.status ?? 1,
    stdout: result.stdout ?? '',
    stderr: result.error ? result.error.message : (result.stderr ?? ''),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2), { gh, log: (line) => console.log(line) });
}
