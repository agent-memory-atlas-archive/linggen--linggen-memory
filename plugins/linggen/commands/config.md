---
description: Point this host at a Linggen — show or set where ling and ling-mem live (loopback, or another machine on your LAN)
---

Run the plugin's config script with the user's arguments, with a 3-minute
timeout (asking another machine waits up to two minutes for a click there):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/config.sh" $ARGUMENTS
```

Show its output verbatim — the address lines, the `Next:` / `All set` line and
the common commands are the guidance; do not reword or summarize them.

The script does the work — read, probe, ask, write, mirror. Do not
re-implement any of it, and do not edit `client.json`, `settings.json` or
Codex's `config.toml` yourself: a config write is mechanical, and a model
improvising a JSON or TOML edit is how a settings file gets mangled.

After a run that changed addresses, add one line: **restart this host**
(Claude Code or Codex) — MCP server URLs are resolved at startup.

What its states mean, if the user asks:

- `ok` — reachable and this machine may use it.
- `not approved` — reachable, but that machine has not allowed this one.
  `--ling-mem <addr>` asks; someone clicks Allow there (Linggen or the
  ling-mem console), and the token arrives on its own.
- `no answer` — nothing listens there: the daemon is down, that machine is set
  to "This machine only" (ling-mem console → Settings → Network), or a
  firewall blocks the port.

Usage:

- `/linggen:config` — show where things are, and the next step
- `/linggen:config --ling-mem 192.168.1.5:9528` — memory on another machine (approve it there)
- `/linggen:config --ling-mem 192.168.1.5:9528 --token <t>` — the same, with a token in hand
- `/linggen:config --local` — back to this machine
