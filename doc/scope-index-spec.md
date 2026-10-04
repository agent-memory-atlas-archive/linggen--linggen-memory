---
type: spec
reader: Coding agent and users
audience: implementation — scope, index, field cleanup
status: draft 2026-10-04, awaiting go
---

# Scope and index

How a memory row knows where it belongs, and how a session gets the few
rows it should always see. Modelled on Claude Code's CLAUDE.md: rules live
in directories, and a session loads its directory and every parent.

## Why

- A session used to load every `type=preference` row at start ("standing
  rules"). Rules for Sanji, Linux builds and Downloads then rode into a chat
  about an insurance company. Removed 2026-10-04 (89ec847); this spec
  replaces it with something narrower.
- `contexts` does two jobs: a free subject tag (184 values, three spellings
  of `linggen`) and the app isolation namespace. Host recall ignores it.
- `tags` is read by nothing. 61 of 100 tagged rows say `digest`, which no
  code checks.
- `cwd` records where the agent stood, which is often too wide (`skills`
  root) or too narrow (one chapter's folder) for what the row is about.

## Model

| Layer | Holds | Enters context |
|---|---|---|
| core | Who the person is. No cwd, ever. | Every session. |
| index | Rows with `indexed = true` | Session start and on cd: rows whose cwd is the session dir or a parent. One line each: `hook (id=…)`. |
| everything else | Long-term rows | Per-turn recall, by subject, within the recall scope. |

The index is a query, not a stored document. Edit a row's hook or flag and
the next session sees it.

## Fields

| Field | Change |
|---|---|
| `cwd` | Now the row's **scope**: the directory it is about. Agent-chosen from host candidates; default = session cwd. Null = about the person, visible everywhere (non-core). |
| `hook` | **New.** One line, ≤ 80 chars, written by the model. Required for `preference` and `decision`. |
| `indexed` | **New.** Bool. Puts the row in its directory's index. |
| `from` | Added to the `memory_add` MCP schema. A statement the user made is `from=user`. |
| `contexts` | **Removed.** App isolation moves to cwd (below); subject tags go — recall ranks on content. |
| `tags` | **Removed.** A digest is known by the rows whose `superseded_by` points at it. |
| `host`, `source_session` | Unchanged, host-filled. The CC hook fills `source_session` itself; recall.sh stops asking the model to. |

## Choosing the scope

The host knows the paths; only the model knows what the row is about. So the
host offers candidates and the model picks.

- **Root**: the git root of the session cwd; outside git, the directory the
  session started in (CC `CLAUDE_PROJECT_DIR`, Linggen `session.cwd`).
- **Candidates**: every directory from root down to the session cwd, plus
  root's subdirectories that carry a marker (`SKILL.md`, `CLAUDE.md`,
  `README*`, `Cargo.toml`, `package.json`, `pubspec.yaml`), plus parents of
  root up to (not including) `$HOME`.
- The host shows the candidates once at session start and on cd:
  `Memory scopes here: skills, skills/lingjing, skills/dj, … (default: <cwd>)`.
- The model passes `scope` (a candidate) on `memory_add`. The host turns it
  into an absolute `cwd`. The daemon rejects anything that is not an
  existing directory inside root or a parent of root below `$HOME`, and
  falls back to the session cwd.
- Examples: a 《九鼎录》 writing rule → `skills/lingjing`. A DJ lyrics lesson
  → `skills/dj`. "Commit straight to main" → `~/workspace`.
- Dream may propose a move; the console edits it directly.

## Recall scope

- **Owner sessions**: rows under root (any depth), rows at a parent of root,
  and rows with no cwd. Applied in the daemon before ranking.
- **Skill sessions** (cwd under `~/.linggen/skills/<name>`): rows under that
  directory only, no person rows — today's app isolation, keyed by path
  instead of `contexts`. `is_project_dir` stops rejecting
  `~/.linggen/skills/*`; `~/.linggen` itself and `$HOME` stay non-scopes.
- **No root** (`$HOME`, `~/.linggen`, temp — Yinyue, a plain chat): rows with
  no cwd, plus at most 2 rows filed under a directory when they match the
  question strongly (cosine ≥ `no_root_project_min_score`, default 0.70 —
  chosen from live queries 2026-10-04: small talk peaked at 0.68, on-topic
  project questions reached 0.71–0.79). `preference` rows with a cwd never
  qualify: dev and project rules must not ride into everyday chat; facts and
  decisions about the work can. Applied in the daemon's search, so every host
  gets the same rule. (Approved by Hanli 2026-10-04.)

## Index loading

- Rows with `indexed = true` and cwd equal to the session cwd or any parent
  of it, nearest directory first, then by `updated_at`.
- Rendered under `## Index — <dir>` headings, one `- hook (id=…)` line per
  row. The agent reads a row in full with `memory_get` when a hook bears on
  the task.
- Budget 3000 chars across all directories; the nearest directories win, and
  a skipped count is printed.
- Engine: reloaded when `check_working_folder_change` fires. CC: SessionStart
  only (no cd hook); recall covers the rest.

### Who sets `indexed`

- The model, when the user states a standing rule ("以后都…", "always…").
- Dream proposes adds and drops as review items; the person confirms.
- The console toggles it per row.
- Rules already written in a project file get a pointer hook instead of the
  rule: `写作规则见 story/jiuding-lu/DESIGN.md § 五·六`.

## Bug fixes shipped with this

1. Omitted `tier` goes to episodic, as the protocol says (today: semantic).
2. `from` on the `memory_add` schema; recall lines show `from`.
3. One `source_session` story: host-filled everywhere, never asked of the
   model.
4. Merges keep the surviving row's cwd unless it is empty (HTTP cross-tier
   merge overwrote it). Digests take the members' common scope; chains
   rows carry cwd.
5. `replace_ids` keeps the loser's tier.
6. One TTL clock: `COALESCE(occurred_at, created_at)` for list and sweep.
7. CLI `filter_body` forwards `include_expired`, `superseded_by`,
   `source_session` and every `--type`.
8. Protocol text: `occurred_at` is for days and TTL, not ranking.

## Migration (reviewed before it writes)

1. Back up the store.
2. App rows: `contexts` ∈ {cfo, dj, health} and written by that skill's
   session (from `source_session`) → cwd `~/.linggen/skills/<name>`.
3. Rows under `skills/lingjing/**` and lingjing rows at `skills` root →
   proposed `skills/lingjing`.
4. Global dev rules (commit on main, one question at a time, 9527 testing,
   subagents…) → proposed `~/workspace`. Sanji rules → `rust/sanji`.
5. Hooks generated for every preference and decision; `indexed` proposed
   for `from=user` preferences.
6. Fix the timezone core row's cwd (core has none).
7. Drop `contexts` and `tags` columns; schema version bump with a
   registered migration step.

Steps 3–5 land as a console review page: row, current cwd → proposed cwd,
proposed hook, proposed index flag. Nothing writes until the person accepts.

## Surfaces that move together

ling-mem (schema, store filters, session_start, MCP schema and
instructions, CLI), engine (`memory_mcp.rs` stamping, auto-recall scope,
core block + index, skill-session scope), CC plugin (stamp-cwd.sh,
autostart.sh, recall.sh; marketplace and cache copies), OpenClaw plugin,
memory SKILL.md and references, `agents/memory.md` and the dream mission,
console UI, phone memory pull.
