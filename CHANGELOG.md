# Changelog

What each template version changes for the projects made from it. A project moves to a version with `.\.template\Update-Project.ps1`.

## v0.8.0

### Update twice, or once from a clone

Every earlier version of `.template\Update-Project.ps1` fails to hand an update over to the newer script when the template is cloned over a URL, as it is from GitHub, and runs its own, older update logic instead. It read the newer script with `git checkout` from a blob-filtered clone, which doesn't fetch the file. v0.8.0 fixes this, but the fix reaches a project only on its second update after this release: the first update to v0.8.0 still runs the project's old script, which installs the fixed one. That first run also commits on whatever branch is checked out, so switch to a branch of its own first.

To run the v0.8.0 logic on the first update instead, run the wrapper from a clone of this repository at v0.8.0: `git clone --branch v0.8.0 https://github.com/polewskm/project-template.git`, then `.\Update-Project.ps1 -Path <project>` in that clone.

### Changes

- `Update-Project.ps1` reads the target version's copy of itself with `git show` and hands the update over to it, and clones the template in full.
- `Update-Project.ps1` refuses to commit on the default branch (the branch `origin/HEAD` names). Run it on a branch of its own, such as `git switch -c build/project-template-v0.8.0`, or pass `-NoCommit`.
- `Update-Project.ps1` replaces Copier's "Make sure Git >= 2.24 is installed" warning, a false alarm with Git 2.55 and later, with what it means (copier-org/copier#2759).
- `Update-Project.ps1` shows the template's changes to project-owned files rendered with the project's answers, not as Jinja, and leaves out a change the project's answers don't reach.
- `Update-Project.ps1` and `Adopt-Project.ps1` no longer set `core.hooksPath` in a clone that has hooks in `.git/hooks`, which a hooks path turns off. They say how to run both.
- `Adopt-Project.ps1` asks to re-admit `Directory.Build.props` and `build/ProjectTemplate.props` in each `.dockerignore` and in each CI file that lists `Directory.Build.props`.
- The plan executor reports a Done-when command it couldn't run and leaves the check to the coordinator, instead of reporting a check of its own.
- `CLAUDE.md`, `.template/Update-Project.ps1` and `Directory.Build.props` end with a newline.
