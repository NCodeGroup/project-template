---
description: Run address-feedback on one pull request round after round until it merges or closes — fix, push, comment /review so NCode Review reviews the new commits, wait for its review and new comments, and recommend the merge
argument-hint: The pull request, such as #42, owner/repo#42 or its URL, optionally only:<login> or exclude:<login>, and wait:<hours> to change the 24-hour wait with nothing to answer
role: orchestrator
append-format: false
targets: Claude
---
Handle every open comment and discussion on this pull request, round after round, in this session, until it merges or closes:

{{INPUT}}

You coordinate. Each round is one pass of `address-feedback`: read its installed file, `.claude/commands/address-feedback.md` in the repository, or `~/.claude/commands/address-feedback.md` when the repository has none, and follow its body after the front matter yourself, in this session, with the request above less its `wait:<hours>` word, and with the changes Each Pass makes. `<number>`, `<head>`, `<default>`, an item and its verdicts are as `address-feedback` defines them.

## Rules

- `address-feedback`'s Rules apply in every pass. Never merge the pull request, mark it ready for review or draft, turn on auto-merge, resolve a review thread, dismiss a review or an alert, close it, edit its title or description, force-push, or push with `--no-verify`. Every discussion ends fixed and replied to, or answered, and I resolve it.
- Ask me once, in the first pass's Start item 6, and never again in this run: my answer covers every later pass. Where a command says to ask me, wait for me or stop to ask, stop the run instead, as Stop says.
- Write every comment and reply to a temporary file outside the repository with your file-writing tool, pass the file to the command, and delete it afterwards.

## Start

1. Take a `wait:<hours>` word, such as `wait:72`, out of the request. It sets the wait limit: how long the run waits with nothing to answer, 24 hours when the request has no such word.
2. Run the first pass now, as Each Pass says. In the run summary its Start item 6 shows, also say: that the run checks the pull request every five minutes until it merges or closes, and stops once it has waited the wait limit, in hours, with nothing to answer; that each pass that pushes fixes is a round, and costs about one plan run on Opus, one orchestrate-plan run and up to three reviews; that after the `landing` line's `max-review-rounds` rounds, or a pass that finds nothing to fix, it recommends the merge in a comment, and comments from authors who may ask for a fix still get their fixes after that; and, when the project runs NCode Review, as NCode Review Findings below says, that it comments `/review` after each push so the bot reviews the new commits, waits for that review, takes only its blocker and should-fix findings, replies at most twice on each of its threads and lists its nits.

## Each Pass

A pass follows `address-feedback` from its Start item 1 through its Reply, with these changes:

1. Start item 3: when the pull request's state is `MERGED` or `CLOSED` (`merged` or `closed` on GitLab), the run ends: go on with Report.
2. Start item 5: these aren't items either; list each in the report instead:
   - an NCode Review finding that isn't to act on, as NCode Review Findings says: its nits, its protected findings and those for me; and every top-level comment and review summary NCode Review writes;
   - a thread whose first comment is from a review bot the `landing` line's `review-bots` names and two or more of whose comments start with `Autopilot:`: it is for me, and never gets a third reply;
   - once the merge is recommended, as Recommend the Merge says, every NCode Review finding.

   When no item is left, the pass ends there, before `address-feedback`'s Plan: go on with Wait.
3. Start item 6 runs in the first pass only. Later passes show no summary and go on.
4. Push: after its item 5 pushes, note `<pushed>`, the commit `git rev-parse HEAD` prints in the worktree. {{PROMPT:_review-request}} Note the time with `Get-Date`: NCode Review's review of `<pushed>` is awaited from then on, as Wait says.
5. Reply: as it says. When it leaves the worktree in place, stop the run, as Stop says: `/continue-plan feedback-<number>` shows it.

When the pass stops in `address-feedback`, follow its Stop, then stop the run: go on with Report.
