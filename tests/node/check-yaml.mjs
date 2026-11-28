// Parses each YAML file named on the command line with the yaml package, and prints "<file>: <first line of the
// problem>" for each one that has an error or a warning: a syntax error, a duplicate key, more than one document, or
// a tag the parser doesn't know, such as !custom. Exits 1 if any has. tests/Test-Template.ps1 runs it for
// its "valid YAML" check of every rendered .yml and .yaml file.
import { readFileSync } from 'node:fs';
import YAML from 'yaml';

let failed = false;
for (const file of process.argv.slice(2)) {
  let problem;
  try {
    const doc = YAML.parseDocument(readFileSync(file, 'utf8'), { logLevel: 'error' });
    problem = doc.errors[0] ?? doc.warnings[0];
  } catch (error) {
    problem = error;
  }
  if (problem) {
    failed = true;
    console.log(`${file}: ${String(problem?.message ?? problem).split('\n')[0]}`);
  }
}
process.exitCode = failed ? 1 : 0;
