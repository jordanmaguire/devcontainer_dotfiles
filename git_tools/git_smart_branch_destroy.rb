#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/selection_prompt"

branches = Branch.all.reject(&:protected?)
selected_branches =
  SelectionPrompt.new(
    allow_multiple: true,
    choices: branches,
    noun: "branch",
    plural_noun: "branches",
    prompt_message: "Destroy one or more branches:",
  ).prompt_for_selection

puts
if !selected_branches.nil? && selected_branches.any?
  selected_branches.map(&:name).each do |selected_branch|
    result = Git.run("branch", "-D", selected_branch)
    if result.success?
      puts "Destroyed #{selected_branch}"
    else
      puts "Could not destroy #{selected_branch}: #{result.message}"
    end
  end
end
