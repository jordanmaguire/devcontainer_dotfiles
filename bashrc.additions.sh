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
alias gbr="git branch"
alias gcom="git co master"
alias gcop="git co -"
alias gd="git diff"
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
alias gsd="~/dotfiles/git_tools/git_smart_branch_destroy.rb"
alias gco="~/dotfiles/git_tools/git_smart_checkout.rb"
alias gsp="~/dotfiles/git_tools/git_smart_prune.rb"
# TODO: I have no idea where this tool went. I evidently deleted the code for it.
#       I can see use for this - maybe it shows the branches in your current tree first and then
#       other branches after.
# alias grib="git_smart_rebase"
