#!/usr/bin/env bash
# Shared by autostart.sh, recall.sh and stamp-cwd.sh: where a session stands,
# for memory (ling-mem doc/scope-index-spec.md). Hosts hand the daemon paths;
# the daemon owns the rules (which dirs can hold rows, what a root sees).
#
# memory_root <cwd> — the session's root: the git root above <cwd> (never
# $HOME, which is a dotfiles repo at most), else CLAUDE_PROJECT_DIR (where a
# Claude Code session started), else <cwd>. A skill's own dir
# (~/.linggen/skills/<name>) is its own root.
memory_root() {
    local cwd="$1" root=""
    [ -n "$cwd" ] || return 0
    case "$cwd" in
        "$HOME/.linggen/skills/"*)
            local rest="${cwd#"$HOME/.linggen/skills/"}"
            printf '%s\n' "$HOME/.linggen/skills/${rest%%/*}"
            return 0
            ;;
    esac
    if command -v git >/dev/null 2>&1; then
        root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    fi
    # Never $HOME, and never a repo ABOVE it (a cwd under $HOME whose git
    # root is outside it): the daemon's find_root stops at $HOME too.
    [ "$root" = "$HOME" ] && root=""
    case "$cwd" in "$HOME"|"$HOME"/*) case "$root" in "$HOME"/*) ;; *) root="" ;; esac ;; esac
    [ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-}"
    [ -n "$root" ] || root="$cwd"
    printf '%s\n' "$root"
}

# is_project_dir <dir> — can rows be about this dir? Not $HOME, not
# ~/.linggen outside a skill's own dir, not a temp dir. Same rule as the
# daemon's memory::scope::is_scope_dir and the engine's is_project_dir.
is_project_dir() {
    local d="$1" tmp="${TMPDIR:-/tmp}"
    case "$d" in
        "") return 1 ;;
        "$HOME/.linggen/skills/"?*) return 0 ;;
        "$HOME"|"$HOME/"|"$HOME/.linggen"|"$HOME/.linggen/"*) return 1 ;;
        "${tmp%/}"|"${tmp%/}/"*|/tmp|/tmp/*|/private/tmp|/private/tmp/*|/private/var/folders/*|/var/folders/*) return 1 ;;
    esac
    return 0
}
