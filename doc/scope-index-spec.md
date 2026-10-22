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
- `cwd` recorded where the agent stood, which is often too wide (`skills`
  root) or too narrow (one chapter's folder) for what the row is about. The
  stored field is now `scope`.

## Model

| Layer | Holds | Enters context |
|---|---|---|
| core | Who the person is. No scope, ever. | Every session. |
| index | Rows with `indexed = true` | Session start and on cd: rows whose scope is the session dir or a parent. One line each: `summary (id=…)`. |
| everything else | Long-term rows | Per-turn recall, by subject, within the recall scope. |

The index is a query, not a stored document. Edit a row's summary or flag and
the next session sees it.

## Fields

| Field | Change |
|---|---|
| `scope` | Was `cwd`. The absolute directory the row is about. Agent-chosen from host candidates; default = session cwd. Null = about the person, visible everywhere (non-core). |
| `summary` | **New** (first shipped as `hook`). One line, ≤ 80 chars, written by the model. Matters only on indexed rows: it is what the index shows. Without one the index shows the content's opening. |
| `indexed` | **New.** Bool. Puts the row in its directory's index. |
| `from` | Added to the `memory_add` MCP schema. A statement the user made is `from=user`. |
| `contexts` | **Removed.** App isolation moves to scope (below); subject tags go — recall ranks on content. |
| `tags` | **Removed.** A digest is known by the rows whose `superseded_by` points at it. |
| `host`, `source_session` | Unchanged, host-filled. The CC hook fills `source_session` itself; recall.sh stops asking the model to. |

## Choosing the scope

The host knows the paths; only the model knows what the row is about. So the
host offers candidates and the model picks.

- **Root**: the git root of the session cwd; outside git, the directory the
  session started in (CC `CLAUDE_PROJECT_DIR`, Linggen `session.cwd`).
  It is the root of where the session STARTED and does not move when the
  shell cds below it: the candidates were shown against it, so every stamp
  (add, search, recall, session start) sends that same root. Claude Code
  hands hooks the shell's cwd; rooting each call at that cwd's own git root
  re-based the candidates — a session started in a non-git workspace and
  cd'd into one of its repos had `linggen/linggen` and an absolute sibling
  dir dropped for cwd (2026-10-05). A cwd outside the start dir roots on its
  own (`scope.sh` `session_root`).
- **Candidates**: every directory from root down to the session cwd, plus
  root's subdirectories that carry a marker (`SKILL.md`, `CLAUDE.md`,
  `README*`, `Cargo.toml`, `package.json`, `pubspec.yaml`), plus parents of
  root up to (not including) `$HOME`.
- The host shows the candidates once at session start and on cd:
  `Memory scopes here: skills, skills/lingjing, skills/dj, … (default: <cwd>)`.
- The model passes `scope` (a candidate) on `memory_add`. The daemon turns
  it into an absolute stored `scope`, resolved against the host-filled
  `cwd` and `root` (request params only). It rejects anything that is not
  an existing directory inside root or a parent of root below `$HOME`, and
  falls back to the session cwd. A host that cannot stamp (Codex has no
  input rewrite) sends neither: then an absolute or `~/` scope naming an
  existing directory that can hold rows is taken as named, and anything
  else leaves the row unscoped.
- MCP arguments are brought to the tool schema's types before they reach
  the REST layer (`"false"` → `false`, `"5"` → `5`, a lone id → `[id]`): a
  Claude Code session sent `indexed: "false"` and the add failed.
- Examples: a 《九鼎录》 writing rule → `skills/lingjing`. A DJ lyrics lesson
  → `skills/dj`. "Commit straight to main" → `~/workspace`.
- The dream moves a row it is sure is misfiled (`memory_update` `scope`, or
  `global:true`); the console edits it directly.

## Recall scope

- **Skill sessions** (cwd under `~/.linggen/skills/<name>`): rows under that
  directory only, no person rows — app isolation, keyed by path. A hard
  filter in SQL, on search and list, unweighed. `~/.linggen` itself and
  `$HOME` stay non-scopes.
- **Every other search with a root** — a project, `$HOME`, `~/.linggen`, a
  temp dir alike: no scope filter. Every live row except the apps' (rows
  under `~/.linggen/skills/` never reach non-app recall: dev memory stays
  out of game memory and game memory out of dev chat) is scored and
  weighed by where its directory sits relative to the root (below).
  (Decided by Hanli 2026-10-22; replaces the owner filter — rows under
  root, at its parents and with no scope — and the no-root rule of person
  rows plus at most two strong non-preference matches, cosine ≥
  `no_root_project_min_score`. That config key is gone.)
- **No root** sent: no filter, no weight.
- **`list`** with a root keeps the filter: an owner root sees rows under it,
  at its parents and with no scope; `$HOME`/`~/.linggen`/temp see rows with
  no scope. A browse has no score to weigh.

### Recall weights

`d` = steps from the root up to the common ancestor plus steps down to the
row's directory. One table, `scope::KIN_WEIGHTS`:

| Row's directory | Kin | Weight |
|---|---|---|
| the root itself (d = 0) | same | 1.1 |
| one step below the root | child | 1.0 |
| one step above the root | parent | 0.9 |
| d = 2: sibling, grandparent, grandchild | near | 0.85 |
| d > 2: another project; any project from `~/.linggen/workspace` | far | 0.8 |
| no scope (about the person) | person | 1.0 |

- `score = (cosine + keyword_boost) × weight`. The weight multiplies the
  UNCLAMPED hybrid (it can exceed 1): clamping first would cap a far row at
  exactly its weight. `min_score` gates `score`; rows rank by it; the shown
  `hybrid_score` is it clamped to 1.0. The JSON also carries `score`
  (cosine), `raw_hybrid` and `scope_weight` for inspection.
- Rows deeper below the root count by distance like any other, so a
  session at `$HOME` does not take every project for its own.
- The pool is every live non-app row — the flat scan an unscoped search
  always ran (about 1.8k rows, ~0.6 s per two-table search in a debug
  build). Revisit with an ANN index near 100k rows.
- Keyword boost tokens: a run of one script. CJK runs index as character
  bigrams (a lone character as itself), so `和move有什么不同` yields `move`
  and `不同`. Query terms of two ASCII characters or fewer (`go`, `s`) earn
  no boost: they match by chance and, being rare, weighed most. Embeddings
  are unchanged.
- Tuned 2026-10-22 on a copy of the live store (1,785 non-app rows), 22
  real questions across Linggen, Lingjing, Sanji, ling-mem and plain-life
  roots, floor 0.7. Started from Hanli's 1.2 / 1.0 / 0.9 / 0.8 / 0.7 / 1.0:
  - **same 1.2 → 1.1.** Same-dir hybrids crowd at 0.60–0.70, so 1.2 let
    every row ≥ 0.58 through: 111 Sanji rows for one camera question, and
    small talk ("thanks, that's all for today") recalled two Sanji rows.
    1.1 lets no small talk in and keeps every relevant same-dir top hit.
  - **far 0.7 → 0.8, near 0.8 → 0.85.** Every far or near row whose hybrid
    cleared 0.82 was relevant (an explicit Sanji question from Linggen at
    0.93; the cat's name filed under `linggen/linggen`); the strongest far
    noise was 0.77. 0.8 admits hybrid ≥ 0.875 only — a Sanji row needs a
    near-exact match to reach a Linggen or plain-life question.
  - **parent 0.9, child 1.0, person 1.0** kept: the parent rows are where
    the cross-repo rules live (WebRTC law, 9527 restarts). At 0.9 small
    talk still pulls two parent persona rows (0.81, 0.79 hybrid), but 0.85
    would drop a relevant 0.80 restart rule — not separable by weight.
  - **min_score 0.7 still fits.** At 0.6 (the daemon's
    `recall_min_score` default) a broad Sanji question passes 150+ rows.

## Index loading

- Rows with `indexed = true` and scope equal to the session cwd or any parent
  of it, nearest directory first, then by `updated_at`.
- Rendered under `## Index — <dir>` headings, one `- summary (id=…)` line per
  row (the content's opening when the row has no summary). The agent reads a
  row in full with `memory_get` when a line bears on the task.
- Budget 3000 chars across all directories, the closing line and the
  skipped note included; the nearest directories win, and a skipped count is
  printed.
- Engine: reloaded when `check_working_folder_change` fires. CC: SessionStart
  only (no cd hook); recall covers the rest.

### Who sets `indexed`

- The model, when the user states a standing rule ("以后都…", "always…").
- The dream applies adds and drops itself when sure (a from=user standing
  rule not indexed → `indexed:true` + summary; an indexed row that is no
  standing rule → `indexed:false`). Unsure → it leaves the row alone.
- The console toggles it per row.
- Rules already written in a project file get a pointer summary instead of
  the rule: `写作规则见 story/jiuding-lu/DESIGN.md § 五·六`.

## Bug fixes shipped with this

1. Omitted `tier` goes to episodic, as the protocol says (today: semantic).
2. `from` on the `memory_add` schema; recall lines show `from`.
3. One `source_session` story: host-filled everywhere, never asked of the
   model.
4. Merges keep the surviving row's scope unless it is empty (HTTP cross-tier
   merge overwrote it). Digests take the members' common scope; chains
   rows carry scope.
5. `replace_ids` keeps the loser's tier.
6. One TTL clock: `COALESCE(occurred_at, created_at)` for list and sweep.
7. CLI `filter_body` forwards `include_expired`, `superseded_by`,
   `source_session` and every `--type`.
8. Protocol text: `occurred_at` is for days and TTL, not ranking.

## Migration

The schema v2 step (`doc/schema-versioning.md`) drops `contexts` and
`tags` and renames `hook` → `summary`, `cwd` → `scope`, values carried. It
runs only on `ling-mem apply-schema --yes` (daemon:
`POST /api/schema/apply {"confirm":true}`), never at open:

1. Back up the store to `~/.linggen/memory/backups/schema-v2-<UTC stamp>/`.
2. Reshape both tables.
3. Stamp the SCHEMA_VERSION sidecar 2.

Until then the binary reads and writes a v1 store as it is, and the sidecar
stays 1 so an older binary still opens it. Nobody reviews scope by hand:
the dream fixes a wrong scope, index flag or summary on its own when sure
(the memory skill's `references/dream-flow.md` § Scope and index lane).

## Surfaces that move together

ling-mem (schema, store filters, session_start, MCP schema and
instructions, CLI), engine (`memory_mcp.rs` stamping, auto-recall scope,
core block + index, skill-session scope), CC plugin (stamp-cwd.sh,
autostart.sh, recall.sh; marketplace and cache copies), OpenClaw plugin,
memory SKILL.md and references, `agents/memory.md` and the dream mission,
console UI, phone memory pull.
