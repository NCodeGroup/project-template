#!/usr/bin/env bash
#
# session-start.sh - bootstrap the tools a Claude Code cloud session needs.
#
# The SessionStart hook in .claude/settings.json runs this file. In a Claude Code cloud session (CLAUDE_CODE_REMOTE
# is "true") it runs every ensure-*.sh in this folder, in name order, each with its own bash, so one that fails never
# stops the others; it prints the name of one that exits non-zero. It does nothing on a developer's own machine, and
# it always exits 0, so it never blocks a session.
#
# The template ships ensure-pwsh.sh, and ensure-nvs.sh for a project that uses Node.js. A project bootstraps a tool of
# its own by adding .claude/hooks/ensure-<tool>.sh, which template updates leave alone. Such a script should do
# nothing outside a cloud session and when its tool is already there, print at most a line or two, and exit 0.
#
# This file comes from the project template, and template updates replace it.

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
for script in "$dir"/ensure-*.sh; do
    [ -f "$script" ] || continue
    bash "$script" || echo "session-start: ${script##*/} exited $?"
done
exit 0
