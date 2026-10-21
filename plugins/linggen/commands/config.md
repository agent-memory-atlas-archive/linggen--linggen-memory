---
description: Point this host at a Linggen — show or set where ling and ling-mem live (loopback, or another machine on your LAN)
---

Run the plugin's config script with the user's arguments and show its output verbatim:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh" $ARGUMENTS
```

Give the command a 3-minute timeout: asking another machine waits up to two
minutes for a click there.

The script does the work — read, probe, write, report. Do not re-implement any
of it, and do not edit `client.json`, `settings.json` or Codex's `config.toml`
yourself: a config write is mechanical, and a model improvising a JSON or TOML
edit is how a settings file gets mangled.

Then, in one or two lines:

- If addresses changed, say **restart this host** (Claude Code or Codex) — MCP
  server URLs are resolved at startup, so this session still talks to the old
  ones.
- If it printed `Approve <name> on the Mac…`, it asked that machine to connect
  and waited for the click there (Linggen or the ling-mem console). Approved
  means it is set up; denied or expired is said in one line.
- If a probe says `no answer`, nothing is listening there — on the local
  machine, the daemon may simply be down; on another machine, it may be set to
  "This machine only" (ling-mem console → Settings → Network), or a firewall
  blocks the port.

Usage the user may not know:

- `/linggen:config` — show what is configured and probe it
- `/linggen:config --ling-mem 192.168.1.5:9528` — memory on another machine (approve it there)
- `/linggen:config --ling-mem 192.168.1.5:9528 --token <t>` — the same, with a token in hand
- `/linggen:config --local` — back to this machine
