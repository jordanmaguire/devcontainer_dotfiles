#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/selection_prompt"

# The gco shell function cds into whatever this prints, so everything else goes to stderr.
path_output = $stdout
$stdout = $stderr

branches = Branch.all
selected_branch =
  SelectionPrompt.new(
    choices: branches,
    noun: "branch",
    plural_noun: "branches",
    prompt_message: "Checkout a branch:",
  ).prompt_for_selection

puts
if selected_branch.nil?
  # Cancelled
elsif selected_branch.current?
  puts "Already on #{ selected_branch.name }"
elsif selected_branch.checked_out_elsewhere?
  # git refuses to check out a branch another worktree has, so go to that worktree instead.
  worktree = selected_branch.worktree
  if worktree.missing?
    puts "#{ selected_branch.name } is checked out in #{ worktree.display_path }, which has been deleted. Run gsp to clean it up."
    exit(1)
  end

  puts "#{ selected_branch.name } is checked out in #{ worktree.display_path }"
  path_output.puts(worktree.path)
else
  result = Git.run("checkout", selected_branch.name)
  puts result.message unless result.message.empty?
  exit(1) unless result.success?
end
