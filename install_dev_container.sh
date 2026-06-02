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

echo "Linked Claude config from $DOTFILES_DIR/claude into $CLAUDE_DIR"
