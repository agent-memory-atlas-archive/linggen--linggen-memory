#!/usr/bin/env bash
# Point the plugin's hooks at the eval's scratch ling-mem, never the real 9528.
# Hosts are written as 0.0.0.0 (not 127.0.0.1) so autostart.sh treats both
# daemons as remote: no binary install, no daemon start, no engine download.
# Port 29548 is fixed: scripts/plugin-eval.sh starts the scratch daemon there.
set -eu
curl -sf --max-time 2 http://127.0.0.1:29548/api/health >/dev/null \
  || { echo "scratch ling-mem not up on 29548 — run ./scripts/check.sh eval" >&2; exit 1; }
mkdir -p "$HOME/.linggen"
printf '{"ling_mem":"http://0.0.0.0:29548","ling":"http://0.0.0.0:1"}\n' >"$HOME/.linggen/client.json"
# Workspace: a non-git start dir holding the lingjing repo with a story/ dir.
mkdir -p lingjing/story && git init -q lingjing && echo '# story' > lingjing/story/README.md
