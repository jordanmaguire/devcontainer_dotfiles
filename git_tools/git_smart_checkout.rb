#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_selection_prompt"

# A branch checked out in another worktree can't be checked out here, so we go to that worktree
# instead. A script can't change its parent shell's directory, so the `gco` shell function passes
# a file in GCO_CD_FILE for us to write the destination to, and does the cd itself.
def change_to_worktree(branch)
  unless Dir.exist?(branch.worktree_path)
    puts "#{ branch.name } is checked out in a worktree that no longer exists: #{ branch.worktree_path }"
    puts "Run `git worktree prune` to clean it up."
    return
  end

  # Land in the same subdirectory we're in now (e.g. app/), if the worktree has it
  destination = File.expand_path(`git rev-parse --show-prefix`.strip, branch.worktree_path)
  destination = branch.worktree_path unless Dir.exist?(destination)

  if ENV["GCO_CD_FILE"]
    File.write(ENV["GCO_CD_FILE"], destination)
  else
    puts "#{ branch.name } is checked out in another worktree:"
    puts
    puts "  cd #{ destination }"
  end
end

branches = BranchParser.new(`git branch --format="#{BranchParser::FORMAT}"`).branches
selected_branch =
  BranchSelectionPrompt.new(
    branches: branches,
    prompt_message: "Checkout a branch:",
  ).prompt_for_branch_selection

puts
if selected_branch&.in_other_worktree?
  change_to_worktree(selected_branch)
elsif selected_branch
  `git checkout #{ selected_branch.name }`
end
