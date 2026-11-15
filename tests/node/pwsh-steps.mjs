// Prints, as a JSON array of { file, step, run }, every step in the YAML files named on the command line that runs
// under pwsh, with its run: script: a workflow job's step by its own shell, else its job's defaults.run.shell, else the
// file's; a composite action's runs.steps by its own shell alone. step is the step's name, else its id, else "".
// A file that doesn't parse fails the script; warnings, such as for an unknown tag, are left to check-yaml.mjs, so
// nothing but the JSON reaches the output. tests/Test-Template.ps1's Get-PwshParseError runs it for its "every pwsh
// run: block parses" checks.
import { readFileSync } from 'node:fs';
import YAML from 'yaml';

const isMap = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const runShell = (owner) => {
  const defaults = isMap(owner) ? owner.defaults : undefined;
  const run = isMap(defaults) ? defaults.run : undefined;
  return isMap(run) ? run.shell : undefined;
};

const out = [];
for (const file of process.argv.slice(2)) {
  const doc = YAML.parse(readFileSync(file, 'utf8'), { logLevel: 'error' });
  if (!isMap(doc)) continue;
  const groups = [];
  const docShell = runShell(doc);
  for (const job of isMap(doc.jobs) ? Object.values(doc.jobs) : []) {
    if (!isMap(job)) continue;
    groups.push([job.steps, runShell(job) || docShell]);
  }
  if (isMap(doc.runs)) groups.push([doc.runs.steps, undefined]);
  for (const [steps, shell] of groups) {
    for (const step of Array.isArray(steps) ? steps : []) {
      if (isMap(step) && (step.shell || shell) === 'pwsh' && typeof step.run === 'string') {
        out.push({ file, step: step.name || step.id || '', run: step.run });
      }
    }
  }
}
console.log(JSON.stringify(out));
