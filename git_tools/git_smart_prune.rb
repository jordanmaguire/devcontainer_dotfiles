#!/usr/bin/env ruby

require_relative "lib/branch_parser"

class BranchDeletionPrompt
  RESERVED_BRANCHES = ["main", "master"]

  def initialize(branches)
    @branches = branches
  end

  def prompt_to_delete_merged_branches
    deleteable_branches = @branches - RESERVED_BRANCHES
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
    deleteable_branches.each do |branch_name|
      puts "  #{ branch_name }"
    end
    puts
    # Use print rather than puts so that the number the user types show on the same line
    print "Type 'y' to delete these branches, or anything else to cancel: "
    gets.strip == "y"
  end

  private def delete_branches(deleteable_branches)
    deleteable_branches.each do |branch_name|
      command = "git branch -d #{ branch_name }"
      puts "#{ command }"
      `#{ command }`
    end
  end
end

# Run `git remote prune origin` first to delete any remote references to the
# branches we have checked out locally that have already been deleted
`git remote prune origin`
puts

# Prompt the user to delete any of the branches that are merged into the
# current branch
branches = BranchParser.new(`git branch --merged`).branches
BranchDeletionPrompt.new(branches).prompt_to_delete_merged_branches
