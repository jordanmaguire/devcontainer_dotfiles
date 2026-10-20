#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/prompt"
require_relative "lib/selection_prompt"

# A branch in another worktree can only be deleted once that worktree is removed.
# Returns whether the branch is now free to delete.
def remove_worktree_for(branch)
  worktree = branch.worktree
  if worktree.locked?
    puts "Skipped #{ branch.name }: #{ worktree.display_path } is locked (#{ worktree.lock_reason || "no reason given" })."
    puts "  Run `git worktree unlock #{ worktree.path }` first."
    return false
  end

  force = false
  if worktree.status == :modified || worktree.status == :untracked
    force = Prompt.confirm?("#{ worktree.display_path } has #{ worktree.status } files. Type 'y' to discard them and remove it:")
    unless force
      puts "Skipped #{ branch.name }"
      return false
    end
  end

  result = worktree.remove(force:)
  if result.success?
    puts "Removed worktree #{ worktree.display_path }"
  else
    puts "Could not remove worktree #{ worktree.display_path }: #{ result.message }"
  end
  result.success?
end

# Neither the current worktree's branch nor the main worktree's can be freed by removing a worktree.
branches = Branch.all.reject { _1.protected? || _1.current? || _1.worktree&.main? }
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
  selected_branches.each do |selected_branch|
    next if selected_branch.worktree && !remove_worktree_for(selected_branch)

    result = Git.run("branch", "-D", selected_branch.name)
    if result.success?
      puts "Destroyed #{selected_branch.name}"
    else
      puts "Could not destroy #{selected_branch.name}: #{result.message}"
    end
  end
end
