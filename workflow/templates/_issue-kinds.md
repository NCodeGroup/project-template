Read the issue's type first, its `type.name` in `gh api repos/{owner}/{repo}/issues/<number>`: a `Bug` is a bugfix, unless its labels map to security, and an `Epic` is no kind of plan: decompose-issue splits it into stories, and it is never planned. A `Feature` or a `Task`, or an issue without a type, takes its kind from its labels.

Map the issue's labels to a kind of plan. Compare each label in lowercase, ignoring a prefix that ends in `:`, `::` or `/`, so `type: bug`, `type::bug` and `kind/bug` all count as `bug`:

| Labels | Kind |
|---|---|
| `bug`, `defect`, `regression` | bugfix |
| `enhancement`, `feature`, `feature request`, `tooling` | feature |
| `documentation`, `docs` | docs |
| `security`, `vulnerability` | security |
| `performance`, `perf` | performance |
| `test`, `tests`, `testing` | tests |
| `refactor`, `refactoring`, `tech-debt`, `technical debt`, `cleanup` | refactor |
| `dependencies`, `upgrade`, `migration` | migration |
| `template-update` | template-update |

When no label maps, judge the kind from the issue's title and body. When the labels map to more than one kind, or the text points to a different kind than the labels do, pick the kind of the main change the issue asks for.
