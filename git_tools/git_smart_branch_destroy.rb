#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/branch_selection_prompt"
require_relative "lib/git"

branches = Branch.all
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
    result = Git.run("branch", "-D", selected_branch)
    if result.success?
      puts "Destroyed #{selected_branch}"
    else
      puts "Could not destroy #{selected_branch}: #{result.message}"
    end
  end
end
