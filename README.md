# Dev Container dotfiles

This repo contains some dotfiles I use in dev containers.

This includes a collection of git tools I created to improve my workflow.

## Setup

In VS Code

> Settings > Remote [Dev Container]

1. Set "Dotfiles > Install Command" to

```
install_dev_container.sh
```

2. Set "Dotfiles > Repository" to

```
https://github.com/jordanmaguire/devcontainer_dotfiles
```

Restart VS Code and the dotfiles will be installed in the path specified in "Dotfiles > Target Path" which is "~/dotfiles" by default.

You may lose this configuration when rebuilding your container.

Since this is git repo on a filesystem you can update the dotfiles directly in the dev container. Ensure you push your changes as the dotfiles are blown away semi-regularly by VS Code.

## Git tools

Aliases and shell functions from `bashrc.additions.sh`. The branch lists mark the current branch with `*` and branches checked out in another worktree with `+`, as `git branch` does.

| Command | Script | What it does |
|---------|--------|--------------|
| `gbr` | `git_smart_branch.rb` | Lists branches by most recent commit, with unpushed commits and the worktree each is checked out in |
| `gco` | `git_smart_checkout.rb` | Checks out a branch, or cds into the worktree that already has it |
| `gsd` | `git_smart_branch_destroy.rb` | Destroys branches, removing their worktree first and asking before discarding changes |
| `gsp` | `git_smart_prune.rb` | Deletes branches merged into origin's default branch or deleted from the remote, with their clean worktrees |
| `gsl` | `git_smart_log.rb` | Shows the current branch's commits with diff stats |
| `gwl` | `git_smart_worktree_switch.rb` | Lists worktrees and cds into the one picked |
| `gwt [branch]` | `git_smart_worktree_add.rb` | Creates a worktree for a branch and cds into it |
| `grib` | `git_smart_rebase.rb` | Rebases interactively onto a branch picked from a list |
| `gcom` | — | Goes to master: cds into the worktree that has it, or checks it out |

`gco`, `gwl` and `gwt` are shell functions rather than aliases because a script cannot change its parent shell's directory. The script prints the worktree path on stdout, with everything else on stderr, and the function cds into it.

`gsl`, `csm`, `grim` and `grib` measure against the branch's PR base when the VS Code GitHub extension has recorded one (`branch.<name>.github-pr-base-branch`), otherwise `origin/HEAD`. If `origin/HEAD` is missing, set it with `git remote set-head origin --auto`.

`gwt` starts new branches from a freshly fetched `origin/HEAD` with `--no-track`, so they never track master. It is configured with git config:

- `smarttools.worktreeRoot`: where worktrees go, relative to the main worktree. Defaults to `.claude/worktrees`.
- `smarttools.worktreeCopy`: a glob of gitignored files to copy from the main worktree. It can be given more than once, and defaults to `**/.env`. `node_modules` and `vendor` folders are never searched.
