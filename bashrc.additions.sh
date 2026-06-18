# -A show folders starting with ., but not the entries for "." and "..", which will be in every
#    folder. This is different from -a, which will show "." and "..".
# -F show a trailing / for directories helping to visually indicate folders. The -G option
#    will also show them as blue. Show * for executables. There are other symbols but they
#    aren't too relevant to my workflow.
alias ls="ls -AF --color"

# Command line tool shortcuts. I'll be cold in the ground before I type a full command. I need to
# save my finger bones for deadlifts and video games I can't waste them on keystrokes here.
alias bs="./bin/start"
alias cucu="cucumber"

# Git
# Short for "commits since master".
alias csm="git log master..HEAD --oneline"
alias ga="git add"
alias gcom="git co master"
alias gcop="git co -"
alias gd="git diff"
alias gl="git log"
alias gp="git push"
alias gpl="git pull"
alias gra="git rebase --abort"
alias grc="git rebase --continue"
alias grs="git rebase --skip"
alias grb="git rebase --committer-date-is-author-date"
alias gri="git rebase -i"
alias grim="git rebase -i master"
alias gst="git status"
alias diffupstream="git diff @{upstream}"

# Git Tools - I named these a decade ago. I don't think the names are accurate enough, but
# I'm not going to waste time renaming them.
alias gbr="~/dotfiles/git_tools/git_smart_branch.rb"
alias gco="~/dotfiles/git_tools/git_smart_checkout.rb"
alias gsl="~/dotfiles/git_tools/git_smart_log.rb"
alias gsd="~/dotfiles/git_tools/git_smart_branch_destroy.rb"
alias gsp="~/dotfiles/git_tools/git_smart_prune.rb"
# TODO: I have no idea where this tool went. I evidently deleted the code for it.
#       I can see use for this - maybe it shows the branches in your current tree first and then
#       other branches after.
# alias grib="git_smart_rebase"

# Repair stale VS Code IPC socket so `code --wait` (git's editor) works in
# long-lived shells whose original VS Code window has since closed. Without
# this, git commands fail with "Unable to connect to VS Code server" / ENOENT
# on a dead /tmp/vscode-ipc-*.sock. On each prompt, if the current socket is
# still valid we return immediately; otherwise we scan newest-first and adopt
# the first socket that has a live listener.
__refresh_vscode_ipc() {
  [ -S "$VSCODE_IPC_HOOK_CLI" ] && return
  local s
  for s in $(ls -t /tmp/vscode-ipc-*.sock 2>/dev/null); do
    if python3 -c "import socket,sys; socket.socket(socket.AF_UNIX,socket.SOCK_STREAM).connect(sys.argv[1])" "$s" 2>/dev/null; then
      export VSCODE_IPC_HOOK_CLI="$s"
      return
    fi
  done
}
PROMPT_COMMAND="__refresh_vscode_ipc${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
