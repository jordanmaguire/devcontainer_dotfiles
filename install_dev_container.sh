#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"

BASHRC_SOURCE_LINE="source \"$DOTFILES_DIR/bashrc.additions.sh\""
if ! grep -qF "$BASHRC_SOURCE_LINE" "${HOME}/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "$BASHRC_SOURCE_LINE"
    } >> "${HOME}/.bashrc"
fi

link_claude_dir() {
    local src="$1"
    local dst="$2"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    find "$src" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec ln -sfn {} "$dst/" \;
}

link_claude_file() {
    local src="$1"
    local dst="$2"
    [ -f "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$src" "$dst"
}

link_claude_dir "$DOTFILES_DIR/claude/skills"   "$CLAUDE_DIR/skills"
link_claude_dir "$DOTFILES_DIR/claude/agents"   "$CLAUDE_DIR/agents"
link_claude_dir "$DOTFILES_DIR/claude/commands" "$CLAUDE_DIR/commands"
link_claude_file "$DOTFILES_DIR/claude/settings.json" "$CLAUDE_DIR/settings.json"
link_claude_file "$DOTFILES_DIR/claude/CLAUDE.md"     "$CLAUDE_DIR/CLAUDE.md"

echo "Linked Claude config from $DOTFILES_DIR/claude into $CLAUDE_DIR"

# Linked into each repo under /workspaces rather than set through a global core.hooksPath, because
# a repo-level core.hooksPath would override the global one. A hook somebody else put there is
# left alone.
link_git_hooks() {
    local repo hooks_dir hook dst
    for repo in /workspaces/*/; do
        [ -e "$repo/.git" ] || continue
        hooks_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" || continue
        mkdir -p "$hooks_dir"
        for hook in "$DOTFILES_DIR"/git_hooks/*; do
            dst="$hooks_dir/$(basename "$hook")"
            if [ -e "$dst" ] && [ ! -L "$dst" ]; then
                echo "Skipped $dst: a hook that isn't a symlink is already there" >&2
                continue
            fi
            ln -sfn "$hook" "$dst"
            echo "Linked $hook into $hooks_dir"
        done
    done
}

link_git_hooks

# Last on purpose: set -e stops here if GitHub credentials or sudo aren't available during bootstrap.
# Linked into /usr/local/bin because ~/.local/bin isn't on PATH for the SessionStart hook.
[ -d "$HOME/.dusc/skills" ] || git clone git@github.com:dusc-dev/dusc-skills.git "$HOME/.dusc/skills"
"$HOME/.dusc/skills/bin/dusc-skills" install
sudo ln -sfn "$HOME/.dusc/skills/bin/dusc-skills" /usr/local/bin/dusc-skills
