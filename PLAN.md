# Handoff plan: NCode documentation site, brand and baseline work

Written so another session can continue if this one stops. It holds no credentials and nothing private.

## Done and merged (2026-11-16)
- NCodeGroup/docs#1: the shared Astro Starlight toolchain, released as v0.1.0 (tag 2eb506f9668b74ee854cd005042dfc056c07ccb6). Follow-ups: docs#2 vendor the brand release, #3 phone layout for tables and listings, #4 drop the output-folder guard once Astro compares paths, #5 npm behavior inside min-release-age, #6 default 404 page.
- NCodeGroup/Buffers#66 and #67: documentation site content (13 pages and the landing page), compiled samples in tests/NCode.Buffers.Site.Tests, evidence checks in the gate, docs.yml pinned to the toolchain's v0.1.0 commit. Buffers#68 lists the remaining 13 pages.
- NCodeGroup/brand#1: Instrument design system, released as v0.1.0 (tag 88482a17fb4210670dc4919692d2240f3f5413ac). Follow-ups: brand#2 to #7.

## In progress
1. project-template fix on branch claude/trusting-maxwell-syoxdm (ADR-0024: add the code-scanning rule only where CodeQL analyzes a language; ADR-0025: turn off approval of the most recent push where no approval is required). Finish the review fixes (three surviving mutations and the refused-write notice), run tests/Test-RepositoryBaseline.ps1, Test-DecisionIndex, Test-ChangelogHeadings and Test-ScriptAnalyzer, commit, push, open a draft pull request, answer NCode Review on every finding, nits included, and comment /review (up to 3 rounds). Drop this PLAN.md before merging.

## Next, in the owner's choice of order
2. docs#2: vendor brand v0.1.0 into NCodeGroup/docs with vendoring/vendor-brand.mjs and its lock; move src/styles/theme.css to the --nc- names and starlight.css's mapping; remove vendor/instrument.
3. NCodeGroup/identity: apply the Instrument Material UI theme to @ncode/ui (data from brand's mui/, derive.mjs and fonts; add font-src 'self' to the page policies and amend ADR-1256).
4. NCodeGroup/identity: rename the frontend workspace packages from @ncode/* to @nidentity/* (the owner's npm scopes are @ncodegroup and @nidentity; @ncode is not theirs).
5. Buffers#68: write the remaining site pages, each claim backed by a compiled sample or an evidence-checked link.

## Rules that bind this work
- Commits stay under the owner's identity, unsigned by agents, with no attribution lines (owner's decision).
- Every review finding is fixed or answered with evidence, and replied to ("Autopilot:" first); agents never resolve threads.
- Never push to a default branch; draft pull requests; subscribe to each pull request's activity.
- Node.js, then Go, then PowerShell for tooling; never Python.
- Never point a test or command at a real system path outside a scratch folder.
- Push often, so nothing exists only in a container.
