// Renders each _exclude pattern of the copier.yml named on the command line with nunjucks and no answers, and prints
// the patterns that render to more than whitespace, or that fail to render, with the error, joined by "; ". Exits 1
// if any does, or if copier.yml has no _exclude list: a pattern must exclude nothing until the answers are known.
// tests/Test-Template.ps1 runs it for its "copier.yml: _exclude patterns exclude nothing without the answers" check.
//
// Copier renders the patterns with Jinja2, whose undefined value renders empty and tests false but fails on an
// attribute or item lookup ({{ foo.bar }}, {{ foo['bar'] }}); nunjucks reads those as undefined, so the script makes
// such a lookup fail as Jinja2's does. A call of an undefined name fails in both. Jinja2 also fails on arithmetic
// and ordering comparisons with an undefined value ({{ foo + 1 }}, {% if foo < 2 %}), which nunjucks evaluates without
// an error, and this script doesn't catch those.
import { readFileSync } from 'node:fs';
import nunjucks from 'nunjucks';
import YAML from 'yaml';

const { memberLookup } = nunjucks.runtime;
nunjucks.runtime.memberLookup = (obj, val) => {
  if (obj === undefined) throw new Error(`attribute or item '${val}' of an undefined value`);
  return memberLookup(obj, val);
};
const firstLine = (error) =>
  String(error?.message ?? error)
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line && line !== '(unknown path)')[0] ?? '';

const config = YAML.parse(readFileSync(process.argv[2], 'utf8'), { logLevel: 'error' });
const patterns = config?._exclude;
const bad = [];
if (!Array.isArray(patterns)) {
  bad.push('_exclude is missing or not a list');
} else {
  const env = new nunjucks.Environment(null, { autoescape: false });
  for (const pattern of patterns) {
    if (typeof pattern !== 'string') {
      bad.push(`${JSON.stringify(pattern)} (not a string)`);
      continue;
    }
    try {
      if (env.renderString(pattern, {}).trim()) bad.push(pattern);
    } catch (error) {
      bad.push(`${pattern} (${firstLine(error)})`);
    }
  }
}
console.log(bad.join('; '));
process.exitCode = bad.length ? 1 : 0;
