A story's body has these parts, in this order, the sections the organization's issue forms ask for (ADR-0042 in `docs/decisions/project-template/`):

- `Part of #<epic>.` as its first line, when it belongs to an epic.
- `## What`: the outcome, the rules and decision records it builds on, and how its acceptance is checked. A bug's What says what happens, what should happen instead and how to reproduce it.
- `## Not in this issue`: what it leaves out, naming the story that takes each part, when one does.
- `## Depends on`: the issues it is blocked by, such as `#41, #42.`, or `Nothing.`

An epic's body has `## Goal`, then `## Design`, a link to its design in `docs/designs/` or `None.`, then `## Stories`. Once its stories are filed, Stories says that they are the epic's sub-issues, in the order their "blocked by" links give, and lists none of them.
