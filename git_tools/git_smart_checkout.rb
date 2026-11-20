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

  change_directory_to(branch.worktree_path, "#{ branch.name } is checked out in another worktree:")
end

def change_directory_to(worktree_path, message)
  # Land in the same subdirectory we're in now (e.g. app/), if the worktree has it
  destination = File.expand_path(`git rev-parse --show-prefix`.strip, worktree_path)
  destination = worktree_path unless Dir.exist?(destination)

  if ENV["GCO_CD_FILE"]
    File.write(ENV["GCO_CD_FILE"], destination)
  else
    puts message
    puts
    puts "  cd #{ destination }"
  end
end

# A linked worktree has its own git dir under the main repo's .git/worktrees/, so it differs from
# the common dir. In the main worktree the two are the same.
def in_linked_worktree?
  File.expand_path(`git rev-parse --git-dir`.strip) != File.expand_path(`git rev-parse --git-common-dir`.strip)
end

# The main worktree is always listed first
def main_worktree_path
  `git worktree list --porcelain`.lines.first.delete_prefix("worktree ").strip
end

# Linked worktrees stay on the branch they were made for, so a fresh checkout goes to the main
# worktree and we follow it there.
def checkout_in_main_worktree(branch)
  main_path = main_worktree_path
  return unless system("git", "-C", main_path, "checkout", branch.name)

  change_directory_to(main_path, "Checked out #{ branch.name } in the main worktree:")
end

branches = BranchParser.new(`git branch --format="#{BranchParser::FORMAT}"`).branches
# Given a branch name (as `gcom` does with master) we skip the prompt and go straight to it
requested_branch_name = ARGV.first
selected_branch =
  if requested_branch_name
    branches.find { _1.name == requested_branch_name } || abort("No branch named #{ requested_branch_name }")
  else
    BranchSelectionPrompt.new(
      branches: branches,
      prompt_message: "Checkout a branch:",
    ).prompt_for_branch_selection
  end

puts
if selected_branch&.in_other_worktree?
  change_to_worktree(selected_branch)
elsif selected_branch && in_linked_worktree?
  checkout_in_main_worktree(selected_branch)
elsif selected_branch
  system("git", "checkout", selected_branch.name)
end
