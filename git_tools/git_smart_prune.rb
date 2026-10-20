#!/usr/bin/env ruby

require_relative "lib/base_branch"
require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/prompt"

class BranchDeletionPrompt
  def initialize(base_branch:, merged_branches:, gone_branches:)
    @base_branch = base_branch
    # Only a clean worktree is removed along with its branch, so nothing uncommitted is lost
    @skipped_branches, @merged_branches = merged_branches.partition { skip_reason(_1) }
    skipped_gone_branches, @gone_branches = gone_branches.partition { skip_reason(_1) }
    @skipped_branches += skipped_gone_branches
  end

  def prompt_to_delete_merged_branches
    print_skipped_branches
    if @merged_branches.empty? && @gone_branches.empty?
      puts "There are no merged branches to delete."
    elsif prompt_to_delete_branches
      delete_branches(@merged_branches + @gone_branches)
    end
  end

  private def skip_reason(branch)
    worktree = branch.worktree
    if worktree.nil?
      nil
    elsif worktree.locked?
      "its worktree is locked"
    elsif worktree.status == :modified
      "its worktree has modified files"
    elsif worktree.status == :untracked
      "its worktree has untracked files"
    end
  end

  private def prompt_to_delete_branches
    print_section("The following branches have been merged into #{ @base_branch } and can be deleted:", @merged_branches)
    print_section("The following branches have been deleted from the remote, usually after a squash merge:", @gone_branches)
    Prompt.confirm?("Type 'y' to delete these branches and worktrees, or anything else to cancel:")
  end

  private def print_skipped_branches
    return if @skipped_branches.empty?

    puts "Skipping these merged branches, which gsd can destroy once you have checked them:"
    puts
    @skipped_branches.each do |branch|
      puts "  #{ branch.name } (#{ skip_reason(branch) }: #{ branch.worktree.display_path })"
    end
    puts
  end

  private def print_section(heading, branches)
    return if branches.empty?

    puts heading
    puts
    branches.each do |branch|
      worktree_text = branch.worktree ? " (and its worktree #{ branch.worktree.display_path })" : ""
      puts "  #{ branch.name }#{ worktree_text }"
    end
    puts
  end

  # -D rather than -d: git's own check is against HEAD or the upstream, not the base branch,
  # and a squash-merged branch is never merged by its measure.
  private def delete_branches(branches)
    branches.each do |branch|
      if branch.worktree
        puts "git worktree remove #{ branch.worktree.display_path }"
        result = branch.worktree.remove
        unless result.success?
          puts "  #{ result.message }"
          next
        end
      end

      puts "git branch -D #{ branch.name }"
      result = Git.run("branch", "-D", branch.name)
      puts "  #{ result.message }" unless result.success?
    end
  end
end

# Fetch with --prune first so the base branch is current and remote branches deleted after
# merging show up as gone
puts "Fetching from origin…"
fetch = Git.run("fetch", "--prune", "origin")
puts "  #{ fetch.message }" unless fetch.success?

# Forget worktrees whose folders were deleted by hand, freeing their branches
pruned = Git.run("worktree", "prune", "--verbose")
puts pruned.message unless pruned.message.empty?
puts

# Neither the current worktree's branch nor the main worktree's can be freed by removing a worktree
base_branch = BaseBranch.default
candidate = ->(branch) { !branch.protected? && !branch.current? && !branch.worktree&.main? }
merged_branches = Branch.all(merged: base_branch).select(&candidate)
merged_names = merged_branches.map(&:name)
gone_branches = Branch.all.select { candidate.(_1) && _1.upstream_gone? && !merged_names.include?(_1.name) }
BranchDeletionPrompt.new(base_branch:, merged_branches:, gone_branches:).prompt_to_delete_merged_branches
