---
description: Run address-feedback on one pull request round after round until it merges or closes — fix, push, comment /review so NCode Review reviews the new commits, wait for its review and new comments, and recommend the merge
argument-hint: The pull request, such as #42, owner/repo#42 or its URL, optionally only:<login> or exclude:<login>, wait:<hours> to change the 24-hour wait with nothing to answer, and push-branch:<name> for a session's designated branch
role: orchestrator
append-format: false
targets: Claude
---
Handle every open comment and discussion on this pull request, round after round, in this session, until it merges or closes:

{{INPUT}}

You coordinate. Each round is one pass of `address-feedback`: read its installed file, `.claude/commands/address-feedback.md` in the repository, or `~/.claude/commands/address-feedback.md` when the repository has none, and follow its body after the front matter yourself, in this session, with the request above less its `wait:<hours>` word, and with the changes listed under Each Pass below. Between passes, run `Start-Sleep -Seconds 300` as a background command, and run the next pass when it finishes.

{{PROMPT:_run-feedback-body}}
