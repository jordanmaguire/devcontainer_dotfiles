#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_selection_prompt"

branches = BranchParser.new(`git branch --format="#{BranchParser::FORMAT}"`).branches
selected_branches =
  BranchSelectionPrompt.new(
    allow_multiple: true,
    # The current branch can't be deleted out from under us
    branches: branches.reject(&:current?),
    exclude_protected_branches: true,
    prompt_message: "Destroy one or more branches (+ also removes its worktree):",
  ).prompt_for_branch_selection

puts
if !selected_branches.nil? && selected_branches.any?
  selected_branches.each do |selected_branch|
    # git won't delete a branch that's checked out in a worktree, so the worktree goes first.
    # Without --force this refuses if the worktree has modified or untracked files, in which case
    # we leave the branch alone too.
    if selected_branch.in_other_worktree?
      if system("git", "worktree", "remove", selected_branch.worktree_path)
        puts "Removed worktree #{ selected_branch.worktree_path }"
      else
        puts "Skipped #{ selected_branch.name }"
        next
      end
    end

    if system("git", "branch", "-D", selected_branch.name, out: File::NULL)
      puts "Destroyed #{ selected_branch.name }"
    end
  end
end
