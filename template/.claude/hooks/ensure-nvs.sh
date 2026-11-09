#!/usr/bin/env bash
#
# ensure-nvs.sh - make the project's Node.js available through nvs in a Claude Code cloud session.
#
# .template/Use-Node.ps1, the prelude, and .template/use-node.sh select the .node-version Node.js through nvs, and a
# cloud session's container has no nvs. session-start.sh in this folder runs this file, from the SessionStart hook in
# .claude/settings.json. In a cloud session (CLAUDE_CODE_REMOTE is "true") whose project has a .node-version, it clones
# nvs, pinned to the v1.7.1 tag's commit as .gitlab-ci.yml does, into $NVS_HOME (~/.nvs) when nvs.sh isn't there,
# installs and links that Node.js, and, through CLAUDE_ENV_FILE, puts the linked Node.js first on PATH for the
# session's later commands. It does nothing on a developer's own machine, never runs "nvs.sh install" (which edits
# ~/.bashrc), leaves an $NVS_HOME without nvs.sh as it is, prints one line on failure, and always exits 0.
#
# This file comes from the project template, and template updates replace it.

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
project="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
version="$(head -n1 "$project/.node-version" 2>/dev/null | tr -d '\r ')"
[ -n "$version" ] || exit 0

NVS_TAG=v1.7.1
NVS_COMMIT=b87ae9593cd20e7b667e9099240c9befeb50659f
export NVS_HOME="${NVS_HOME:-$HOME/.nvs}"

if [ ! -s "$NVS_HOME/nvs.sh" ]; then
    if [ -e "$NVS_HOME" ]; then
        echo "ensure-nvs: $NVS_HOME exists without nvs.sh; leaving it as it is, so Node.js $version is not installed."
        exit 0
    fi
    if ! git clone --quiet --depth 1 --branch "$NVS_TAG" https://github.com/jasongin/nvs "$NVS_HOME" >/dev/null 2>&1 ||
        [ "$(git -C "$NVS_HOME" rev-parse HEAD 2>/dev/null)" != "$NVS_COMMIT" ]; then
        rm -rf "$NVS_HOME"
        echo "ensure-nvs: cloning nvs $NVS_TAG failed, so Node.js $version is not installed."
        exit 0
    fi
fi

# shellcheck disable=SC1091
. "$NVS_HOME/nvs.sh" >/dev/null 2>&1
if ! type nvs >/dev/null 2>&1; then
    echo "ensure-nvs: loading $NVS_HOME/nvs.sh failed, so Node.js $version is not installed."
    exit 0
fi
if ! { nvs link "$version" >/dev/null 2>&1 || { nvs add "$version" >/dev/null 2>&1 && nvs link "$version" >/dev/null 2>&1; }; }; then
    echo "ensure-nvs: nvs could not install Node.js $version."
    exit 0
fi
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    printf 'export NVS_HOME="%s"\nexport PATH="%s/default/bin:$PATH"\n' "$NVS_HOME" "$NVS_HOME" >>"$CLAUDE_ENV_FILE"
fi
echo "ensure-nvs: Node.js $("$NVS_HOME/default/bin/node" --version 2>/dev/null) from .node-version is linked through nvs."
exit 0
