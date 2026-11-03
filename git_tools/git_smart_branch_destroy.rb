#!/usr/bin/env ruby

require "open3"

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
    # Without --force this refuses if the worktree has modified or untracked files, so we ask
    # before forcing it. If the worktree stays, the branch stays too.
    if selected_branch.in_other_worktree?
      path = selected_branch.worktree_path
      output, status = Open3.capture2e("git", "worktree", "remove", path)

      if !status.success? && output.include?("contains modified or untracked files")
        print "#{ path } has modified or untracked files. Remove it anyway? [y/N] "
        if $stdin.gets.to_s.strip.downcase == "y"
          output, status = Open3.capture2e("git", "worktree", "remove", "--force", path)
        else
          output = ""
        end
      end

      if status.success?
        puts "Removed worktree #{ path }"
      else
        warn output unless output.empty?
        puts "Skipped #{ selected_branch.name }"
        next
      end
    end

    if system("git", "branch", "-D", selected_branch.name, out: File::NULL)
      puts "Destroyed #{ selected_branch.name }"
    end
  end
end
