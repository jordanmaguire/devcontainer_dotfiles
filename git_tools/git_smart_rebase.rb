#!/usr/bin/env ruby

# Interactively rebases the current branch onto a branch picked from a list: the base branch
# first, then the branches the current one is stacked on, then every other branch.

require_relative "lib/base_branch"
require_relative "lib/branch"
require_relative "lib/selection_prompt"

base_names = [BaseBranch.for_branch, BaseBranch.default].uniq
base_branches = base_names.filter_map do |name|
  ref = name.start_with?("origin/") ? "refs/remotes/#{ name }" : "refs/heads/#{ name }"
  Branch.all(refs: ref).first
end

# Branches in the current branch's history that the base branch does not have yet
local_branches = Branch.all.reject { _1.current? || base_names.include?(_1.name) }
merged_into_head = Branch.all(merged: "HEAD").map(&:name)
merged_into_base = Branch.all(merged: base_names.first).map(&:name)
stacked_branches, other_branches = local_branches.partition do |branch|
  merged_into_head.include?(branch.name) && !merged_into_base.include?(branch.name)
end

selected_branch =
  SelectionPrompt.new(
    choices: base_branches + stacked_branches + other_branches,
    noun: "branch",
    plural_noun: "branches",
    prompt_message: "Rebase onto a branch (the base, then branches this one is stacked on):",
  ).prompt_for_selection

if selected_branch
  puts
  puts "git rebase -i #{ selected_branch.name }"
  exec("git", "rebase", "-i", selected_branch.name)
end
