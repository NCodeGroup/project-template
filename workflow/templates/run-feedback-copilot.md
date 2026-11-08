---
description: Run address-feedback on one pull request round after round until it merges or closes — fix, push, comment /review so NCode Review reviews the new commits, wait for its review and new comments, and recommend the merge
argument-hint: The pull request, such as #42, owner/repo#42 or its URL, optionally only:<login> or exclude:<login>, and wait:<hours> to change the 24-hour wait with nothing to answer
role: orchestrator
append-format: false
targets: VSCode, CopilotCli
command: run-feedback
---
Handle every open comment and discussion on this pull request, round after round, in this session, until it merges or closes:

{{INPUT}}

You coordinate. Each round is one pass of `address-feedback`: read its installed file, `.github/skills/address-feedback/SKILL.md` in the repository; else `.github/prompts/address-feedback.prompt.md`; else `~/.copilot/skills/address-feedback/SKILL.md`, and follow its body after the front matter yourself, in this session, with the request above less its `wait:<hours>` word, and with the changes listed under Each Pass below. Between passes, run `Start-Sleep -Seconds 300` in the foreground, with a timeout of at least 330 seconds where the shell tool takes one, and run the next pass once it returns.

{{PROMPT:_run-feedback-body}}
