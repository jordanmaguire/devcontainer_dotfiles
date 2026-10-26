#!/usr/bin/env ruby

require_relative "lib/branch_parser"

class BranchDeletionPrompt
  def initialize(branches)
    # The current branch is always "merged into the current branch" but can't be deleted
    @branches = branches.reject { _1.protected? || _1.current? }
  end

  def prompt_to_delete_merged_branches
    # Branches checked out in other worktrees are left alone. A worktree whose branch hasn't had
    # any commits yet counts as merged, so removing them would throw away work in progress.
    worktree_branches, deleteable_branches = @branches.partition(&:in_other_worktree?)
    display_worktree_branches(worktree_branches)

    if deleteable_branches.any?
      if (ok_to_delete = prompt_to_delete_branches(deleteable_branches))
        delete_branches(deleteable_branches)
      end
    else
      puts "There are no merged branches to delete."
    end
  end

  private def prompt_to_delete_branches(deleteable_branches)
    puts "The following branches have been merged into your current branch and can be deleted:"
    puts
    deleteable_branches.each do |branch|
      puts "  #{ branch.name }"
    end
    puts
    # Use print rather than puts so that the number the user types show on the same line
    print "Type 'y' to delete these branches, or anything else to cancel: "
    gets.strip == "y"
  end

  private def display_worktree_branches(worktree_branches)
    return if worktree_branches.empty?

    puts "The following branches have been merged but are checked out in a worktree, so won't be deleted:"
    puts
    worktree_branches.each do |branch|
      puts "  #{ branch.name.ljust(Branch::MAX_NAME_LENGTH) } #{ branch.worktree_path }"
    end
    puts
  end

  private def delete_branches(deleteable_branches)
    deleteable_branches.each do |branch|
      command = "git branch -d #{ branch.name }"
      puts "#{ command }"
      `#{ command }`
    end
  end
end

# Run `git remote prune origin` first to delete any remote references to the
# branches we have checked out locally that have already been deleted
`git remote prune origin`
# Forget worktrees whose directories have been deleted by hand, otherwise git
# still considers their branches checked out and refuses to delete them
`git worktree prune`
puts

# Prompt the user to delete any of the branches that are merged into the
# current branch
branches = BranchParser.new(`git branch --format="#{BranchParser::FORMAT}" --merged`).branches
BranchDeletionPrompt.new(branches).prompt_to_delete_merged_branches
