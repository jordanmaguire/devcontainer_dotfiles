#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_selection_prompt"

branches = BranchParser.new(`git branch`).branches
selected_branches =
  BranchSelectionPrompt.new(
    allow_multiple: true,
    branches: branches,
    exclude_protected_branches: true,
    prompt_message: "Destroy one or more branches:",
  ).prompt_for_branch_selection

puts
if !selected_branches.nil? && selected_branches.any?
  selected_branches.each do |selected_branch|
    `git branch -D #{selected_branch}`
    puts "Destroyed #{selected_branch}"
  end
end
