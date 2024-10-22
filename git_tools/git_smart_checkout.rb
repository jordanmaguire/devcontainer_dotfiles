#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_selection_prompt"

branches = BranchParser.new(`git branch`).branches
selected_branch =
  BranchSelectionPrompt.new(
    branches: branches,
    prompt_message: "Checkout a branch:",
  ).prompt_for_branch_selection

puts
if selected_branch
  `git checkout #{ selected_branch }`
end
