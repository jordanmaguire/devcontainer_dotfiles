#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/branch_selection_prompt"
require_relative "lib/git"

branches = Branch.all
selected_branch =
  BranchSelectionPrompt.new(
    branches: branches,
    prompt_message: "Checkout a branch:",
  ).prompt_for_branch_selection

puts
if selected_branch
  result = Git.run("checkout", selected_branch)
  puts result.message unless result.message.empty?
  exit(1) unless result.success?
end
