// Tests tools/kanban-board.mjs with a stand-in gh that answers each GraphQL query from a table, so no network call is made.
// tests/Test-KanbanBoard.ps1 runs it: node --test tests/node/kanban-board.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { main, runGh, statusOptions, STATUSES } from '../../tools/kanban-board.mjs';

const TOKEN_WITH_PROJECT = "  - Token scopes: 'gist', 'project', 'read:org', 'repo'\n";
const PROJECT_URL = 'https://github.com/orgs/NCodeGroup/projects/7';

// A stand-in gh: records every call, answers auth from answers.auth and each GraphQL query with the data of the first
// [key, data] pair of answers.graphql whose key the query contains (data may be a function of the variables; an object
// with a raw property is the whole result). Any other query fails.
function stand(answers = {}) {
  const calls = [];
  const lines = [];
  const gh = (args, input) => {
    calls.push({ args, input });
    if (args[0] === 'auth') return answers.auth ?? { code: 0, stdout: TOKEN_WITH_PROJECT, stderr: '' };
    if (args[0] === 'api' && args[1] === 'graphql') {
      const { query, variables } = JSON.parse(input);
      const pair = (answers.graphql ?? []).find(([key]) => query.includes(key));
      if (pair) {
        const data = typeof pair[1] === 'function' ? pair[1](variables) : pair[1];
        if (data?.raw) return data.raw;
        return { code: 0, stdout: JSON.stringify({ data }), stderr: '' };
      }
    }
    return { code: 1, stdout: '', stderr: 'unexpected query' };
  };
  return { gh, calls, lines, log: (line) => lines.push(line) };
}

const project = (number) => ({ id: `P${number}`, number, title: 'Kanban', url: `https://github.com/orgs/NCodeGroup/projects/${number}` });

// The answers of a run on an organization with the given projects, whose project has the given Status options and workflows:
// the organization query answers projectV2 when it asks for a number, and else one page of projectsV2.
function graphqlAnswers({ projects = [], options = [], workflows = [], created = project(7) } = {}) {
  return [
    ['organization(', (variables) => ({
      organization: variables.number === undefined
        ? { id: 'O1', projectsV2: { nodes: projects, pageInfo: { hasNextPage: false, endCursor: null } } }
        : { id: 'O1', projectV2: projects.find((candidate) => candidate.number === variables.number) ?? null },
    })],
    ['repository(owner', { repository: { id: 'R1' } }],
    ['createProjectV2', { createProjectV2: { projectV2: created } }],
    ['linkProjectV2ToRepository', { linkProjectV2ToRepository: { repository: { id: 'R1' } } }],
    ['node(id', { node: { field: { id: 'F1', options }, workflows: { nodes: workflows } } }],
    ['updateProjectV2Field', { updateProjectV2Field: { projectV2Field: { id: 'F1' } } }],
    ['updateProjectV2(', { updateProjectV2: { projectV2: { id: 'P7' } } }],
  ];
}

// The variables of each GraphQL call whose query contains key.
const sent = (calls, key) =>
  calls
    .filter((call) => call.args[0] === 'api' && JSON.parse(call.input).query.includes(key))
    .map((call) => JSON.parse(call.input).variables);

test('--help returns 0, makes no call and logs the usage', async () => {
  const { gh, calls, lines, log } = stand();
  assert.equal(await main(['--help'], { gh, log }), 0);
  assert.equal(calls.length, 0);
  assert.ok(lines.some((line) => line.includes('--owner')));
});

test('no --owner returns 1 with no call', async () => {
  const { gh, calls, log } = stand();
  assert.equal(await main([], { gh, log }), 1);
  assert.equal(calls.length, 0);
});

test('a token without the project scope returns 0 after the auth call and logs the refresh command', async () => {
  const { gh, calls, lines, log } = stand({ auth: { code: 0, stdout: "  - Token scopes: 'gist', 'repo'\n", stderr: '' } });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].args[0], 'auth');
  assert.ok(lines.some((line) => line.includes('gh auth refresh -h github.com -s project')));
});

test('creates the project, links the repository and sets the five statuses in order', async () => {
  const { gh, calls, lines, log } = stand({ graphql: graphqlAnswers({ options: [{ id: 't', name: 'Todo', color: 'GRAY', description: '' }] }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--repo', 'NCodeGroup/app'], { gh, log }), 0);
  assert.equal(sent(calls, 'createProjectV2')[0].title, 'Kanban');
  assert.equal(sent(calls, 'linkProjectV2ToRepository')[0].repositoryId, 'R1');
  const options = sent(calls, 'updateProjectV2Field')[0].options;
  assert.deepEqual(options.map((option) => option.name), STATUSES.map((status) => status.name));
  assert.ok(sent(calls, 'updateProjectV2(')[0].text.includes('At most 2 stories'));
  assert.ok(lines.some((line) => line.endsWith('- board: NCodeGroup/7')));
});

test('adopts --project 3, keeps each existing status and any other option', async () => {
  const existing = [
    { id: 'a', name: 'Todo', color: 'GREEN', description: '' },
    { id: 'b', name: 'In Progress', color: 'YELLOW', description: '' },
    { id: 'c', name: 'Done', color: 'PURPLE', description: '' },
    { id: 'd', name: 'Blocked', color: 'RED', description: '' },
  ];
  const { gh, calls, lines, log } = stand({ graphql: graphqlAnswers({ projects: [project(3)], options: existing }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--project', '3'], { gh, log }), 0);
  assert.equal(sent(calls, 'createProjectV2').length, 0);
  const options = sent(calls, 'updateProjectV2Field')[0].options;
  assert.deepEqual(options.map((option) => option.id), ['a', undefined, 'b', undefined, 'c', 'd']);
  assert.ok(lines.some((line) => line.includes('Blocked')));
});

test('--wip-limit 3 puts the limit in the description', async () => {
  const { gh, calls, log } = stand({ graphql: graphqlAnswers() });
  assert.equal(await main(['--owner', 'NCodeGroup', '--wip-limit', '3'], { gh, log }), 0);
  assert.ok(sent(calls, 'updateProjectV2(')[0].text.includes('At most 3 stories'));
});

test('reports each built-in workflow as on, off or not found', async () => {
  const workflows = [
    { name: 'Item closed', enabled: true },
    { name: 'Pull request merged', enabled: true },
    { name: 'Item added to project', enabled: false },
  ];
  const { gh, lines, log } = stand({ graphql: graphqlAnswers({ workflows }) });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 0);
  assert.ok(lines.includes('- Item closed: on'));
  assert.ok(lines.some((line) => line.startsWith('- Item added to project: off')));
  assert.ok(lines.some((line) => line.startsWith('- Auto-add to project: not found')));
  assert.ok(lines.some((line) => line.includes(`${PROJECT_URL}/workflows`)));
});

test('--project 9 on an organization without it returns 1', async () => {
  const { gh, lines, log } = stand({ graphql: graphqlAnswers({ projects: [project(3)] }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--project', '9'], { gh, log }), 1);
  assert.ok(lines.includes('No project #9 in NCodeGroup.'));
});

test('a failed GraphQL call returns 1 and logs why', async () => {
  const failure = { raw: { code: 1, stdout: '', stderr: 'HTTP 502' } };
  const { gh, lines, log } = stand({ graphql: [['organization(', failure]] });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 1);
  assert.ok(lines.some((line) => line.includes('HTTP 502')));
});

test('statusOptions with no existing option returns the five statuses without ids', () => {
  const { options, kept } = statusOptions([]);
  assert.deepEqual(options, STATUSES.map((status) => ({ ...status })));
  assert.ok(options.every((option) => !('id' in option)));
  assert.deepEqual(kept, []);
});

// The answers of graphqlAnswers(), with the answer for key replaced.
const replace = (answers, key, data) => answers.map(([k, d]) => [k, k === key ? data : d]);
const FAILURE = { raw: { code: 1, stdout: '', stderr: 'HTTP 502' } };

test('with --owner alone, adopts the project titled Kanban and creates none', async () => {
  const { gh, calls, lines, log } = stand({ graphql: graphqlAnswers({ projects: [project(5)] }) });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 0);
  assert.equal(sent(calls, 'createProjectV2').length, 0);
  assert.ok(lines.some((line) => line.startsWith('Adopted project #5: ')));
});

test('--title Other creates a project when only one titled Kanban exists', async () => {
  const { gh, calls, lines, log } = stand({ graphql: graphqlAnswers({ projects: [project(5)] }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--title', 'Other'], { gh, log }), 0);
  assert.equal(sent(calls, 'createProjectV2')[0].title, 'Other');
  assert.ok(lines.some((line) => line.startsWith('Created project #7: ')));
});

for (const args of [
  ['--repo', 'app'],
  ['--repo', 'NCodeGroup/app/x'],
  ['--project', '0'],
  ['--project', 'abc'],
  ['--wip-limit', '0'],
  ['--wip-limit', '100'],
  ['--unknown'],
]) {
  test(`${args.join(' ')} returns 1, logs the usage and calls no gh`, async () => {
    const { gh, calls, lines, log } = stand({ graphql: graphqlAnswers() });
    assert.equal(await main(['--owner', 'NCodeGroup', ...args], { gh, log }), 1);
    assert.equal(calls.length, 0);
    assert.ok(lines.some((line) => line.startsWith('Usage: ')));
  });
}

test('gh not signed in returns 1 after the auth call', async () => {
  const { gh, calls, lines, log } = stand({ auth: { code: 1, stdout: '', stderr: 'You are not logged into any GitHub hosts.' } });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 1);
  assert.equal(calls.length, 1);
  assert.ok(lines.includes("gh isn't signed in to github.com: run gh auth login."));
});

for (const key of ['repository(owner', 'createProjectV2', 'linkProjectV2ToRepository', 'node(id', 'updateProjectV2Field', 'updateProjectV2(']) {
  test(`a failed ${key} call returns 1, logs why and makes no later change`, async () => {
    const { gh, lines, log } = stand({ graphql: replace(graphqlAnswers(), key, FAILURE) });
    assert.equal(await main(['--owner', 'NCodeGroup', '--repo', 'NCodeGroup/app'], { gh, log }), 1);
    assert.ok(lines.includes('gh api graphql failed: HTTP 502'));
    assert.ok(!lines.some((line) => line.startsWith('Add this line')));
  });
}

for (const [what, stdout] of [["that isn't JSON", '<html>Bad gateway</html>'], ['with no data', '{}']]) {
  test(`a mutation that exits 0 with an answer ${what} returns 1 and logs it`, async () => {
    const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'updateProjectV2Field', { raw: { code: 0, stdout, stderr: '' } }) });
    assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 1);
    assert.ok(lines.includes(`gh api graphql failed: ${stdout}`));
    assert.equal(sent(calls, 'updateProjectV2(').length, 0);
  });
}

test('statusOptions gives Backlog the id of Todo when there is no Backlog, matches names ignoring case and keeps every other option', () => {
  const { options, kept } = statusOptions([
    { id: 't', name: 'Todo', color: 'GRAY', description: 'Not started' },
    { id: 'r', name: 'READY', color: 'BLUE', description: '' },
    { id: 'q', name: 'QA', color: 'PINK' },
  ]);
  assert.deepEqual(options.map((option) => option.id), ['t', 'r', undefined, undefined, undefined, 'q']);
  assert.deepEqual(options.map((option) => option.name), [...STATUSES.map((status) => status.name), 'QA']);
  assert.deepEqual(options[5], { id: 'q', name: 'QA', color: 'PINK', description: '' });
  assert.deepEqual(kept, ['QA']);
});

test('statusOptions keeps Todo as another option when there is a Backlog', () => {
  const { options, kept } = statusOptions([
    { id: 'b', name: 'Backlog', color: 'GRAY', description: '' },
    { id: 't', name: 'Todo', color: 'GRAY', description: '' },
  ]);
  assert.equal(options[0].id, 'b');
  assert.deepEqual(kept, ['Todo']);
});

test("finds the project titled Kanban on a later page of the organization's projects", async () => {
  const roadmap = { id: 'P1', number: 1, title: 'Roadmap', url: 'https://github.com/orgs/NCodeGroup/projects/1' };
  const pages = {
    first: { nodes: [roadmap], pageInfo: { hasNextPage: true, endCursor: 'c1' } },
    c1: { nodes: [project(12)], pageInfo: { hasNextPage: false, endCursor: 'c2' } },
  };
  const organization = (variables) => ({ organization: { id: 'O1', projectsV2: pages[variables.after ?? 'first'] } });
  const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'organization(', organization) });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 0);
  assert.deepEqual(sent(calls, 'projectsV2(').map((variables) => variables.after), [null, 'c1']);
  assert.equal(sent(calls, 'createProjectV2').length, 0);
  assert.ok(lines.some((line) => line.startsWith('Adopted project #12: ')));
});

test("--project 3 reads that project by its number, not the organization's list", async () => {
  const { gh, calls, log } = stand({ graphql: graphqlAnswers({ projects: [project(3)] }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--project', '3'], { gh, log }), 0);
  assert.deepEqual(sent(calls, 'projectV2(number').map((variables) => variables.number), [3]);
  assert.equal(sent(calls, 'projectsV2(').length, 0);
});

test('--project 9, which GitHub answers with a NOT_FOUND error, returns 1 and says there is no such project', async () => {
  const answer = { data: { organization: { id: 'O1', projectV2: null } }, errors: [{ type: 'NOT_FOUND', message: 'Could not resolve to a ProjectV2 with the number 9.' }] };
  const notFound = { raw: { code: 1, stdout: JSON.stringify(answer), stderr: 'gh: Could not resolve to a ProjectV2 with the number 9.' } };
  const { gh, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'organization(', notFound) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--project', '9'], { gh, log }), 1);
  assert.ok(lines.includes('No project #9 in NCodeGroup.'));
});

test('runGh stops a gh call after 120 s and reports the timeout as a failure', () => {
  const seen = [];
  const spawn = (command, args, options) => {
    seen.push({ command, args, options });
    return { status: null, signal: 'SIGTERM', stdout: '', stderr: '', error: Object.assign(new Error('spawnSync gh ETIMEDOUT'), { code: 'ETIMEDOUT' }) };
  };
  assert.deepEqual(runGh(['auth', 'status'], undefined, spawn), { code: 1, stdout: '', stderr: 'gh timed out after 120 s' });
  assert.equal(seen[0].command, 'gh');
  assert.equal(seen[0].options.timeout, 120000);
});

test("runGh reports a gh that can't start or is stopped by a signal as a failure, and passes an exit code through", () => {
  assert.deepEqual(runGh([], undefined, () => ({ status: null, error: new Error('spawnSync gh ENOENT') })), { code: 1, stdout: '', stderr: 'spawnSync gh ENOENT' });
  assert.equal(runGh([], undefined, () => ({ status: null, signal: 'SIGKILL', stdout: '', stderr: '' })).code, 1);
  assert.deepEqual(runGh([], undefined, () => ({ status: 0, stdout: 'ok', stderr: '' })), { code: 0, stdout: 'ok', stderr: '' });
});

// The number of GraphQL mutations the calls sent.
const mutations = (calls) => calls.filter((call) => call.args[0] === 'api' && JSON.parse(call.input).query.startsWith('mutation')).length;

for (const args of [[], ['--project', '3']]) {
  test(`an organization answer of null${args.length > 0 ? ` with ${args.join(' ')}` : ''} returns 1, says there is no such organization and sends no mutation`, async () => {
    const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'organization(', { organization: null }) });
    assert.equal(await main(['--owner', 'NCodeGroup', ...args], { gh, log }), 1);
    assert.ok(lines.includes('gh api graphql failed: no organization NCodeGroup.'));
    assert.equal(mutations(calls), 0);
  });
}

test('a repository answer of null with --repo returns 1, says there is no such repository and sends no mutation', async () => {
  const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'repository(owner', { repository: null }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--repo', 'NCodeGroup/app'], { gh, log }), 1);
  assert.ok(lines.includes('gh api graphql failed: no repository NCodeGroup/app.'));
  assert.equal(mutations(calls), 0);
});

test('a createProjectV2 answer with no project returns 1, says none was created and sends no later mutation', async () => {
  const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'createProjectV2', { createProjectV2: { projectV2: null } }) });
  assert.equal(await main(['--owner', 'NCodeGroup', '--repo', 'NCodeGroup/app'], { gh, log }), 1);
  assert.ok(lines.includes('gh api graphql failed: no project was created.'));
  assert.equal(mutations(calls), 1);
  assert.equal(sent(calls, 'linkProjectV2ToRepository').length, 0);
});

test('a project whose Status field is null returns 1, says it has no Status field and sends no later mutation', async () => {
  const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'node(id', { node: { field: null, workflows: { nodes: [] } } }) });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 1);
  assert.ok(lines.includes('The project has no Status field.'));
  assert.equal(sent(calls, 'updateProjectV2Field').length, 0);
  assert.equal(sent(calls, 'updateProjectV2(').length, 0);
});

test('a project with more workflows than one page returns 0, says only the first 50 were read and sends each mutation once', async () => {
  const details = { node: { field: { id: 'F1', options: [] }, workflows: { nodes: [], pageInfo: { hasNextPage: true } } } };
  const { gh, calls, lines, log } = stand({ graphql: replace(graphqlAnswers(), 'node(id', details) });
  assert.equal(await main(['--owner', 'NCodeGroup'], { gh, log }), 0);
  assert.ok(lines.includes('The project has more than 50 workflows, and this read the first 50: check a workflow not found above in its settings.'));
  assert.equal(mutations(calls), 3);
  assert.ok(lines.at(-1).startsWith('Add this line'));
});
