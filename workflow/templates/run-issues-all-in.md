---
description: Take every issue named into one plan and one draft pull request in one session — no questions, every follow-up and finding fixed in that pull request, protected paths included for named issues, a review after every push, no caps — and stop once it is clean and the merge is recommended
argument-hint: Issues to run in one pull request, such as #42 #43, or a filter such as label:bug, and push-branch:<name> to push through a session's designated branch
role: orchestrator
append-format: false
targets: Claude
---
Take these issues from plan to a clean draft pull request, all of them in one plan and one pull request, in this session, until the merge is recommended:

{{INPUT}}

This is `run-issues` with its answers given and its caps lifted. Read its installed file, `.claude/commands/run-issues.md` in the repository, or `~/.claude/commands/run-issues.md` when the repository has none, and follow its body after the front matter yourself, in this session, with the request above and the changes below.

{{PROMPT:_run-issues-all-in-body}}
