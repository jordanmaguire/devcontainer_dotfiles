#!/usr/bin/env ruby

require_relative "lib/base_branch"
require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/prompt"

class BranchDeletionPrompt
  def initialize(base_branch:, merged_branches:, gone_branches:)
    @base_branch = base_branch
    @merged_branches = merged_branches
    @gone_branches = gone_branches
  end

  def prompt_to_delete_merged_branches
    if @merged_branches.empty? && @gone_branches.empty?
      puts "There are no merged branches to delete."
    elsif prompt_to_delete_branches
      delete_branches(@merged_branches + @gone_branches)
    end
  end

  private def prompt_to_delete_branches
    print_section("The following branches have been merged into #{ @base_branch } and can be deleted:", @merged_branches)
    print_section("The following branches have been deleted from the remote, usually after a squash merge:", @gone_branches)
    Prompt.confirm?("Type 'y' to delete these branches, or anything else to cancel:")
  end

  private def print_section(heading, branches)
    return if branches.empty?

    puts heading
    puts
    branches.each do |branch|
      puts "  #{ branch.name }"
    end
    puts
  end

  # -D rather than -d: git's own check is against HEAD or the upstream, not the base branch,
  # and a squash-merged branch is never merged by its measure.
  private def delete_branches(branches)
    branches.each do |branch|
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
puts

# Branches in a worktree, including the current one, cannot be deleted
base_branch = BaseBranch.default
deletable = ->(branch) { !branch.protected? && branch.worktree.nil? }
merged_branches = Branch.all(merged: base_branch).select(&deletable)
merged_names = merged_branches.map(&:name)
gone_branches = Branch.all.select { deletable.(_1) && _1.upstream_gone? && !merged_names.include?(_1.name) }
BranchDeletionPrompt.new(base_branch:, merged_branches:, gone_branches:).prompt_to_delete_merged_branches
