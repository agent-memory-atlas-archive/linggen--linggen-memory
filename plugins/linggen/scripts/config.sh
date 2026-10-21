#!/usr/bin/env bash
# Point this host at a Linggen — `/linggen:config`.
#
# The CLIENT declaration: where THIS machine goes to find `ling` and `ling-mem`.
# On the machine that runs them, that is loopback and nobody ever needs this.
# On a second machine, it is the first machine's LAN address plus a paired
# device token — and nothing has to be installed locally, because the hooks talk
# MCP over HTTP and the memory tools come from the daemon, not a binary.
#
# It is deliberately NOT the engine's `[server].url`. That says where the daemon
# on a machine BINDS. This says where a client CONNECTS. On one machine they
# coincide, which is what makes them easy to confuse; on two they are different
# facts about different hosts.
#
#   config.sh                              # show what is configured, and probe it
#   config.sh --ling http://192.168.1.5:9527
#   config.sh --ling-mem 192.168.1.5:9528  # asks that machine; approve it there
#   config.sh --ling-mem 192.168.1.5:9528 --token <device-token>   # manual
#   config.sh --local                      # back to this machine
#   config.sh --mirror                     # re-mirror client.json into the hosts (hooks)
#
# Writes ~/.linggen/client.json, which the hooks read. Also mirrors the two
# addresses into each host's own MCP wiring, because a plugin's MCP declaration
# cannot read a file: Claude Code's settings.json `env` (its `.mcp.json` takes
# `${VAR}`, expanded at startup), and Codex's config.toml `[mcp_servers.*]`
# tables (Codex expands nothing in a URL, so its plugin declaration is literal
# loopback and an off-machine address must override it there). Then says
# plainly whether that took.

set -u

DATA_DIR="${LINGGEN_DATA_DIR:-$HOME/.linggen}"
CLIENT_FILE="$DATA_DIR/client.json"
CC_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CODEX_CONFIG="${CODEX_HOME:-$HOME/.codex}/config.toml"

DEFAULT_LING="http://127.0.0.1:9527"
DEFAULT_LING_MEM="http://127.0.0.1:9528"

die() { printf '%s\n' "$*" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || die "config: jq is required"
command -v curl >/dev/null 2>&1 || die "config: curl is required"

# ── Arguments ───────────────────────────────────────────────────────────────

ling="" ling_mem="" token="" reset=0 show_only=1 mirror_only=0

while [ $# -gt 0 ]; do
    case "$1" in
        --ling)     ling="${2:-}";     shift 2; show_only=0 ;;
        --ling-mem) ling_mem="${2:-}"; shift 2; show_only=0 ;;
        --token)    token="${2:-}";    shift 2; show_only=0 ;;
        --local)    reset=1;           shift;   show_only=0 ;;
        --mirror)   mirror_only=1;     shift;   show_only=0 ;;
        -h|--help)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          die "config: unknown argument $1" ;;
    esac
done

# `host:port` is accepted and normalised — that is how a person says an address,
# and refusing it would be pedantry.
normalize() {
    local u="$1"
    [ -z "$u" ] && return 0
    case "$u" in http://*|https://*) ;; *) u="http://$u" ;; esac
    printf '%s' "${u%/}"
}

ling="$(normalize "$ling")"
ling_mem="$(normalize "$ling_mem")"

# ── Read, merge, write ──────────────────────────────────────────────────────

current() { [ -r "$CLIENT_FILE" ] && jq -r --arg k "$1" '.[$k] // empty' "$CLIENT_FILE" 2>/dev/null; }

cur_ling="$(current ling)"
cur_ling_mem="$(current ling_mem)"
cur_token="$(current token)"
cur_device_id="$(current device_id)"

if [ "$reset" = 1 ]; then
    new_ling="$DEFAULT_LING"; new_ling_mem="$DEFAULT_LING_MEM"; new_token=""
else
    new_ling="${ling:-${cur_ling:-$DEFAULT_LING}}"
    new_ling_mem="${ling_mem:-${cur_ling_mem:-$DEFAULT_LING_MEM}}"
    new_token="${token:-$cur_token}"
fi

# ── Ask to connect ──────────────────────────────────────────────────────────
#
# Pointed at another machine with no token: ask it. The Mac shows the request
# (Linggen or the ling-mem console); a click there hands this host a token,
# which is saved below like a typed --token. Nobody sees or copies it.

mcp_code() { # $1 base, $2 token — HTTP status of an MCP tools/list
    local auth=()
    [ -n "${2:-}" ] && auth=(-H "x-linggen-device: $2")
    curl -s -o /dev/null -w '%{http_code}' --max-time 5 --connect-timeout 2 \
        -H 'Content-Type: application/json' ${auth[@]+"${auth[@]}"} \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$1/mcp" 2>/dev/null
}

new_uuid() {
    { uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || od -An -N16 -tx1 /dev/urandom | tr -d ' \n'; } | tr 'A-Z' 'a-z'
}

device_id="${cur_device_id:-$(new_uuid)}"
device_name="$(hostname -s 2>/dev/null || hostname)"

ask_status() { # $1 base, $2 request id — prints the status JSON
    curl -s --max-time 5 --connect-timeout 2 "$1/api/connect/status/$2" 2>/dev/null
}

ask_to_connect() { # $1 base — prints the token, or dies with why not
    local base="$1" body reply code rid st
    body="$(jq -nc --arg n "$device_name" --arg d "$device_id" '{device_name: $n, device_id: $d}')"
    reply="$(curl -s -w '\n%{http_code}' --max-time 5 --connect-timeout 2 \
        -H 'Content-Type: application/json' -d "$body" "$base/api/connect/request" 2>/dev/null)"
    code="${reply##*$'\n'}"
    case "$code" in
        200) ;;
        403) die "config: that machine denied $device_name. Un-deny it in its ling-mem console, then retry." ;;
        429) die "config: too many requests — wait a minute and retry." ;;
        *)   die "config: could not ask $base to connect (HTTP $code)." ;;
    esac
    rid="$(printf '%s' "${reply%$'\n'*}" | jq -r '.data.request_id // empty')"
    [ -n "$rid" ] || die "config: $base did not open a request."
    printf 'Approve %s on the Mac (Linggen or the ling-mem console)…\n' "$device_name" >&2
    for _ in $(seq 1 60); do
        st="$(ask_status "$base" "$rid")"
        case "$(printf '%s' "$st" | jq -r '.data.state // empty' 2>/dev/null)" in
            allowed) printf '%s' "$st" | jq -r '.data.device_token // empty'; return 0 ;;
            denied)  die "config: denied on that machine." ;;
            expired) die "config: the request expired — run this again." ;;
        esac
        sleep 2
    done
    die "config: no answer within two minutes — run this again."
}

if [ "$show_only" = 0 ] && [ "$mirror_only" = 0 ] && [ "$reset" = 0 ] && [ -z "$token" ]; then
    case "$(mcp_code "$new_ling_mem" "$new_token")" in
        401|403)
            new_token="$(ask_to_connect "$new_ling_mem")" || exit 1
            [ -n "$new_token" ] || die "config: approved, but no token came back — run this again."
            printf 'Approved.\n' >&2 ;;
    esac
fi

# ── Mirror into Claude Code's env ───────────────────────────────────────────
#
# Derived, never authored here: client.json above is the one place a human
# edits. This exists only because `.mcp.json` cannot read a file.

mirror_cc_env() {
    local host_l port_l host_m port_m
    host_l="${new_ling#*://}"; port_l="${host_l##*:}"; host_l="${host_l%%:*}"
    host_m="${new_ling_mem#*://}"; port_m="${host_m##*:}"; host_m="${host_m%%:*}"
    mkdir -p "$(dirname "$CC_SETTINGS")" 2>/dev/null || return 1
    [ -f "$CC_SETTINGS" ] || printf '{}\n' > "$CC_SETTINGS"
    local tmp="$CC_SETTINGS.tmp.$$"
    jq --arg hl "$host_l" --arg pl "$port_l" --arg hm "$host_m" --arg pm "$port_m" --arg tk "$new_token" '
        .env = ((.env // {})
            + {LINGGEN_HOST: $hl, LINGGEN_PORT: $pl, LING_MEM_HOST: $hm, LING_MEM_PORT: $pm})
            | if $tk == "" then del(.env.LING_MEM_TOKEN) else .env.LING_MEM_TOKEN = $tk end
    ' "$CC_SETTINGS" > "$tmp" 2>/dev/null && mv "$tmp" "$CC_SETTINGS"
}


# ── Mirror into Codex's config.toml ─────────────────────────────────────────
#
# Codex reads the plugin's own `.codex-plugin/mcp.json`, which is literal
# loopback — Codex expands no `${VAR}` in a URL. A `[mcp_servers.<name>]` table
# in config.toml overrides a plugin server of the same name, so that is where an
# off-machine address goes. On loopback the tables are removed and the plugin's
# declaration stands, so a default install leaves no trace here.

mirror_codex_toml() { # exit 2 = no Codex on this machine
    [ -d "$(dirname "$CODEX_CONFIG")" ] || return 2
    [ -f "$CODEX_CONFIG" ] || : > "$CODEX_CONFIG"
    local tmp="$CODEX_CONFIG.tmp.$$"
    # Drop our two tables (sub-tables included) wherever a TOML-aware writer
    # left them — a table runs from its header to the next header or EOF. No
    # BEGIN/END markers: Codex rewrites this file itself and moves comments.
    # One line of lookbehind so the blank line we put before our tables goes
    # with them when they sat at EOF — a round trip leaves the file byte-equal.
    awk '
        function flush() { if (held) { print heldline; held = 0 } }
        /^[[:space:]]*\[mcp_servers\.(ling-mem|linggen)(\.[^]]*)?\]/ { skip = 1; tail = 1; next }
        /^[[:space:]]*\[/ { skip = 0 }
        skip { next }
        { flush(); heldline = $0; held = 1; tail = 0 }
        END { if (held && !(tail && heldline ~ /^[[:space:]]*$/)) print heldline }
    ' "$CODEX_CONFIG" > "$tmp" || { rm -f "$tmp"; return 1; }
    if [ "$new_ling" != "$DEFAULT_LING" ] || [ "$new_ling_mem" != "$DEFAULT_LING_MEM" ]; then
        {
            printf '\n[mcp_servers.linggen]\nurl = "%s/mcp"\n' "$new_ling"
            printf '\n[mcp_servers.ling-mem]\nurl = "%s/mcp"\n' "$new_ling_mem"
            [ -n "$new_token" ] && printf 'http_headers = { "x-linggen-device" = "%s" }\n' "$new_token"
        } >> "$tmp"
    fi
    mv "$tmp" "$CODEX_CONFIG"
}

# ── State, drift, guidance ─────────────────────────────────────────────────

is_local() { # $1 url — this machine?
    local h="${1#*://}"; h="${h%%[:/]*}"
    case "$h" in 127.0.0.1|localhost|::1|"") return 0 ;; *) return 1 ;; esac
}
host_of() { local h="${1#*://}"; printf '%s' "${h%%[:/]*}"; }

state_of() { # $1 base, $2 token — ok | not_approved | no_answer | http_NNN
    local code
    code="$(mcp_code "$1" "${2:-}")"
    case "$code" in
        200) printf ok ;;
        401|403) printf not_approved ;;
        000|"") printf no_answer ;;
        *) printf 'http_%s' "$code" ;;
    esac
}

label() { # $1 state, $2 base — the line's verdict
    case "$1" in
        ok) local ver
            ver="$(curl -fsS --max-time 4 --connect-timeout 2 "$2/api/health" 2>/dev/null \
                | jq -r '.version // .data.version // empty' 2>/dev/null)"
            printf 'ok%s' "$([ -n "$ver" ] && printf ' · %s' "$ver")" ;;
        not_approved) printf 'not approved' ;;
        no_answer) printf 'no answer' ;;
        *) printf 'HTTP %s' "${1#http_}" ;;
    esac
}

# What Claude Code's `.mcp.json` should see vs what its settings env holds.
cc_env_want() {
    local l="${new_ling#*://}" m="${new_ling_mem#*://}"
    printf '%s %s %s %s %s' "${l%%:*}" "${l##*:}" "${m%%:*}" "${m##*:}" "$new_token"
}
cc_env_have() {
    [ -r "$CC_SETTINGS" ] || { printf '127.0.0.1 9527 127.0.0.1 9528 '; return; }
    jq -r '.env // {} | "\(.LINGGEN_HOST // "127.0.0.1") \(.LINGGEN_PORT // "9527") \(.LING_MEM_HOST // "127.0.0.1") \(.LING_MEM_PORT // "9528") \(.LING_MEM_TOKEN // "")"' \
        "$CC_SETTINGS" 2>/dev/null
}
cc_env_drifted() { # no Claude Code here → nothing to drift
    [ -d "$(dirname "$CC_SETTINGS")" ] || return 1
    [ "$(cc_env_want)" != "$(cc_env_have)" ]
}

next_step() { # $1 ling state, $2 ling-mem state
    if cc_env_drifted; then
        echo "Next: run /linggen:config --ling-mem ${new_ling_mem#*://}, then restart Claude Code."
    elif [ "$2" = not_approved ]; then
        echo "Next: run /linggen:config --ling-mem ${new_ling_mem#*://} and click Allow on $(host_of "$new_ling_mem")."
    elif [ "$2" = no_answer ] && is_local "$new_ling_mem"; then
        echo "Next: ling-mem is not running here. Start it: ling-mem start"
    elif [ "$2" = no_answer ]; then
        echo "Next: nothing answers at $(host_of "$new_ling_mem"). Check it is on and shared on LAN."
    elif [ "$1" = no_answer ] && is_local "$new_ling"; then
        echo "Next: Linggen is not running here. Start it: ling --web (or open Linggen.app)."
    elif [ "$1" = not_approved ]; then
        echo "Next: Linggen on $(host_of "$new_ling") has not approved this machine."
    elif is_local "$new_ling_mem"; then
        echo "All set. Change settings at http://localhost:9527/settings"
    else
        echo "All set: memory comes from $(host_of "$new_ling_mem")."
        is_local "$new_ling" && echo "Change settings at http://localhost:9527/settings"
    fi
    return 0
}

guide() {
    local ls ms
    ls="$(state_of "$new_ling" "$new_token")"
    ms="$(state_of "$new_ling_mem" "$new_token")"
    printf 'ling      %s  %s\n' "$new_ling" "$(label "$ls" "$new_ling")"
    printf 'ling-mem  %s  %s\n' "$new_ling_mem" "$(label "$ms" "$new_ling_mem")"
    printf '\n'
    next_step "$ls" "$ms"
    printf '\nCommon:\n'
    printf '  /linggen:config --ling-mem <ip>:9528   use memory on another machine\n'
    printf '  /linggen:config --local                use this machine again\n'
    printf '  /linggen:config                        check again\n'
}

if [ "$show_only" = 1 ]; then
    guide
    exit 0
fi

write_client() {
    mkdir -p "$DATA_DIR" 2>/dev/null || die "config: cannot create $DATA_DIR"
    local tmp="$CLIENT_FILE.tmp.$$"
    jq -n --arg l "$new_ling" --arg m "$new_ling_mem" --arg t "$new_token" --arg d "$device_id" \
        '{ling: $l, ling_mem: $m, token: $t, device_id: $d}' > "$tmp" || die "config: could not write $tmp"
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$CLIENT_FILE" || die "config: could not replace $CLIENT_FILE"
}
# `--mirror` re-mirrors what client.json already says; it never rewrites it.
[ "$mirror_only" = 1 ] || write_client

# `--mirror` (the SessionStart hook): exit 0 when Claude Code's env changed
# and needs a restart, 10 when it already matched.
if [ "$mirror_only" = 1 ]; then
    mirror_codex_toml >/dev/null 2>&1 || true
    cc_env_drifted || exit 10
    mirror_cc_env || exit 1
    exit 0
fi

mirrored=1
mirror_cc_env || mirrored=0
codex_mirrored=1
mirror_codex_toml || codex_mirrored=$?

# ── Report ──────────────────────────────────────────────────────────────────

printf 'wrote %s\n\n' "$CLIENT_FILE"
printf 'ling      %s  %s\n' "$new_ling" "$(label "$(state_of "$new_ling" "$new_token")" "$new_ling")"
printf 'ling-mem  %s  %s\n' "$new_ling_mem" "$(label "$(state_of "$new_ling_mem" "$new_token")" "$new_ling_mem")"
printf '\n'

if [ "$mirrored" = 1 ]; then
    printf 'Claude Code: mirrored into %s (env). Restart it — MCP URLs are resolved at startup.\n' "$CC_SETTINGS"
else
    printf 'Claude Code: could not write %s — the hooks will follow client.json, but the MCP\n' "$CC_SETTINGS"
    printf 'servers will not. Export these in your shell profile instead:\n'
    printf '  export LINGGEN_HOST=%s LINGGEN_PORT=%s\n' "${new_ling#*://}" ""
    printf '  export LING_MEM_HOST=%s\n' "${new_ling_mem#*://}"
fi
case "$codex_mirrored" in
    1) if [ "$new_ling" != "$DEFAULT_LING" ] || [ "$new_ling_mem" != "$DEFAULT_LING_MEM" ]; then
           printf 'Codex: mirrored into %s ([mcp_servers.*]). Restart it.\n' "$CODEX_CONFIG"
       else
           printf 'Codex: loopback — the plugin declaration stands; nothing written to %s.\n' "$CODEX_CONFIG"
       fi ;;
    2) ;;
    *) printf 'Codex: could not write %s — add [mcp_servers.ling-mem] url = "%s/mcp" yourself.\n' "$CODEX_CONFIG" "$new_ling_mem" ;;
esac
