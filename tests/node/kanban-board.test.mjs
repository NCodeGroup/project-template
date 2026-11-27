// Tests tools/kanban-board.mjs with a stand-in gh that answers each GraphQL query from a table, so no network call is made.
// tests/Test-KanbanBoard.ps1 runs it: node --test tests/node/kanban-board.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { main, statusOptions, STATUSES } from '../../tools/kanban-board.mjs';

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

// The answers of a run on an organization with the given projects, whose project has the given Status options and workflows.
function graphqlAnswers({ projects = [], options = [], workflows = [], created = project(7) } = {}) {
  return [
    ['organization(', { organization: { id: 'O1', projectsV2: { nodes: projects } } }],
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
