`<number>`, `<head>`, `<default>`, an item, its verdicts and the run's checkout are as `address-feedback` defines them.

## Rules

- `address-feedback`'s Rules apply in every pass, except that Push below adds `Closes` and `Partly completes` lines to the pull request's description. Never merge the pull request, mark it ready for review or draft, turn on auto-merge, resolve a review thread, dismiss a review or an alert, close it, edit its title, edit its description except to add the `Closes` and `Partly completes` lines Push adds, force-push, or push with `--no-verify`. Every discussion ends remediated and replied to, as ADR-0014 says: fixed in a commit, or answered with why nothing changed, and I resolve it.
- Ask me once, in the first pass's Start item 6, and never again in this run: my answer covers every later pass. Where a command says to ask me, wait for me or stop to ask, stop the run instead, as Stop says.
- Write every comment and reply to a temporary file outside the repository with your file-writing tool, pass the file to the command, and delete it afterwards. {{PROMPT:_reply-check}} {{PROMPT:_github-rest}}

## Start

1. Take a `wait:<hours>` word, such as `wait:72`, out of the request. It sets the wait limit: how long the run waits with nothing to answer, 24 hours when the request has no such word.
2. Run the first pass now, as Each Pass says. In the run summary its Start item 6 shows, also say: that the run checks the pull request every five minutes until it merges or closes, and stops once it has waited the wait limit, in hours, with nothing to answer; that each pass that pushes fixes is a round, and costs about one plan run on Opus, one orchestrate-plan run and up to three reviews; that it recommends the merge in a comment after a pass that leaves every item fixed, declined, answered or put to me, once NCode Review's review of the last push it asked for is in, and still judges, fixes and answers every item that comes after; and, when the project runs NCode Review, as NCode Review Findings below says, that it comments `/review` after each push of its first `max-review-rounds` rounds, the `landing` line's value, so the bot reviews the new commits, and waits for that review, and after those rounds asks for no further review but still fixes and replies; and that it judges every one of the bot's findings, nits included, fixes each that holds and replies at most twice on each of its threads. Say too that, unless the `landing` line says `follow-ups=none`, after each push it adds a `Closes` line to the pull request's description for each open follow-up issue the pull request's work completes, and that once the pull request merges, each one it only partly completes gets a comment and its body rewritten to describe what remains.

## Each Pass

A pass follows `address-feedback` from its Start item 1 through its Reply, with these changes:

1. Start item 3: when the pull request's state is `MERGED` or `CLOSED`, the run ends: when it is `MERGED`, first comment on each issue a `Partly completes` line of the pull request's description names, unless it already has an `Autopilot:` comment that links this pull request, and rewrite its body, as `ship-plan` item 9 says for a line marked ` — partly completes #<number>`; then go on with Report. An earlier run's checkout stays as it is, and `/address-feedback <number>` discards it.
2. Start item 5: these aren't items either; list each in the report instead:
   - an NCode Review finding for me, as NCode Review Findings says; every top-level comment NCode Review writes; and every review summary it writes, but for each finding the summary lists that has no thread of its own, which is an item, as `address-feedback`'s Start item 5 says;
   - a thread whose first comment is from a review bot the `landing` line's `review-bots` names and two or more of whose comments start with `Autopilot:`: it is for me, and never gets a third reply.

   Every other NCode Review finding is an item, whatever its severity, also after the merge is recommended and after the rounds pass `max-review-rounds`: the pass's plan judges it, its `fix` is executed when it holds, and Reply answers it with its verdict. A finding on a protected path is an item too, which `address-feedback`'s Rules make an `ask` unless I approve its change in the first pass's Start item 6. No item gets a reply before the pass's plan has judged it. NCode Review's top-level comments and review summaries get no reply of their own.

   When no item is left, the pass ends there, before `address-feedback`'s Plan: say which threads, comments and review summaries it left out, each with why, then go on with Wait.
3. Start item 6 runs in the first pass only. Later passes show no summary and go on.
4. Push: after its item 7 pushes, note `<pushed>`, the commit `git rev-parse HEAD` prints in the run's checkout: the pass is a round, as Recommend the Merge counts them. Then, in the run's checkout, find the follow-up issues the pull request's work completes. Read the pull request's description first, with `gh pr view <number> --json body --jq .body`. {{PROMPT:_follow-up-check}} When the work completes any issue, write the description to a file with one `Closes <issue reference>` line for each such issue added on a line of its own after its last `Closes` line, or at its end when it has none, and every other line kept, and save it with `gh pr edit <number> --body-file <file>`. Record each issue the work partly completes in the same description, so a restarted run still finds it: one line `Partly completes <issue reference>: <what the pull request did>; <what remains>` after its `Closes` lines, replacing the line an earlier pass wrote for that issue, and deleting that line once a pass finds the work completes the issue and adds its `Closes` line. Save the description as above whenever it changes, also when the work completes no issue. When the rounds, this one included, are more than the `landing` line's `max-review-rounds`, post no `/review` and await no review: the cap limits how often the run asks NCode Review for another review, so a bot that keeps finding new points can't keep the run going, not what the run fixes or answers. Otherwise, the next sentences apply. {{PROMPT:_review-request}} When the project runs NCode Review, note the time with `Get-Date`: NCode Review's review of `<pushed>` is awaited from then on, as Wait says.
5. Reply: as it says. When it leaves the run's checkout in place, stop the run, as Stop says: `/continue-plan` shows it, and `/address-feedback <number>` or `/run-feedback <number>` finishes it.

When the pass stops in `address-feedback`, follow its Stop, then stop the run: go on with Report.

## Wait

Check the pull request every five minutes: sleep between passes as the introduction says. Note the time with `Get-Date` at the first pass, and again at each pass that finds an item.

NCode Review's review of `<pushed>` is awaited after each pass that posted a `/review` comment, as Push says, because that review is the one this run waits for before it recommends the merge. At each later check, before its pass, run `gh api "repos/{owner}/{repo}/commits/<pushed>/check-runs?check_name=Code%20review" --jq '[.check_runs[] | select(.app.slug == "ncode-review" and .status == "completed")] | length'`: NCode Review completes its `Code review` check run on the commit it reviewed once it has posted the review, or once the review failed. When it prints a number above 0, the review has arrived: the pass reads its findings. When an hour has passed since the time Push noted, stop awaiting it, and say in the report that NCode Review didn't review `<pushed>` within an hour.

With no item and no review awaited, end the run once the wait limit has passed since the time you noted: say that the pull request waited the wait limit with nothing to answer, and go on with Report. The pull request stays open as it is.

## Recommend the Merge

Count the rounds: a round is a pass that pushed commits. Recommend the merge after a pass, with no NCode Review review awaited, as Wait says, that gave no item a `fix`, once the run has had a round or that pass found items: every item is then fixed, declined, answered or put to me, and NCode Review's review of the last push the run asked it to review came back with nothing left to act on. A pass that finds no item before the run has had a round recommends nothing, on purpose: nothing on the pull request has been reviewed or answered yet, so the run keeps checking for comments and reviews until the wait limit passes. The recommendation says the pull request can merge, not that feedback stops being handled: every item that comes after it is judged, fixed and answered as before, and the run recommends again only after a later round, once a pass meets these conditions again, so each head of the branch gets at most one recommendation. Post a top-level comment on the pull request, starting with `Autopilot:`, that says the pull request is ready to merge as far as this run can tell, why (the rounds so far, that each item was fixed, declined, answered or put to me, and, once the rounds passed `max-review-rounds`, that the run asked NCode Review for no further review), each item put to me, and every thread still unresolved, by URL, which I resolve before the merge, as the ruleset requires. GitHub: `gh pr comment <number> --body-file <file>`. Then go on with Wait: the run keeps checking until the pull request merges or closes, or the wait limit passes.

## NCode Review Findings

{{PROMPT:_review-bot}}

## Stop

1. When a pass stopped in `address-feedback`, its Stop has run: post nothing more.
2. Say in the report what stopped the run and the question for me. The pull request stays open as it is.

## Report

Finish with one table row per item across every pass: its URL and author, its verdict, the step or commit that fixed it, or the reason, whether it got a reply, and the pass it was in. Under it, list the pull request's link; how the run ended (merged, closed, the wait limit, or a stop and its question for me); the rounds and the commits each pushed; each `/review` comment and whether NCode Review answered it; the merge recommendation's link; each thread still unresolved when the run ended; each NCode Review finding the run listed for me instead of acting on, with its severity; each item on a protected path, with whether I approved its change; each `ask` item; each item left out because of the 40-item limit; and each scanner alert that still needs a dismissal or a fix from me. Also list each `Closes` line Push added to the description, and each issue the work partly completes, with whether it got its comment.
