#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASHRC_SOURCE_LINE="source \"$DOTFILES_DIR/bashrc.additions.sh\""
if ! grep -qF "$BASHRC_SOURCE_LINE" "${HOME}/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "$BASHRC_SOURCE_LINE"
    } >> "${HOME}/.bashrc"
fi
