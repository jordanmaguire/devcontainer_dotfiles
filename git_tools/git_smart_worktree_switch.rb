#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/selection_prompt"
require_relative "lib/style"
require_relative "lib/worktree"

# A worktree as a SelectionPrompt choice, described by the branch it has checked out.
class WorktreeChoice
  def initialize(worktree, branch)
    @worktree = worktree
    @branch = branch
  end

  attr_reader :worktree

  def current?
    @worktree.current?
  end

  def indicator
    current? ? Style.decorate("*", color: recency_color) : " "
  end

  def recency_color
    @branch ? @branch.recency_color : :light_black
  end

  def prompt_text
    return @branch.prompt_text(show_worktree: true) if @branch

    short_head = @worktree.head[0, 7]
    timestamp, relative_time = Git.read("log", "-1", "--format=%ct|%cr", @worktree.head).split("|", 2)
    [
      "(detached at #{ short_head })".ljust(Branch::MAX_NAME_LENGTH),
      Style.decorate(relative_time.to_s, color: :light_black),
      @worktree.status_text,
    ].reject(&:empty?).join(" ")
  end

  # The main worktree first, then the most recently committed to.
  def sort_key
    [@worktree.main? ? 0 : 1, -(@branch&.last_commit_timestamp || 0)]
  end
end

# The gwl shell function cds into whatever this prints, so everything else goes to stderr.
path_output = $stdout
$stdout = $stderr

worktrees = Worktree.all
if worktrees.length == 1
  puts "There are no other worktrees. Use gwt to create one."
  exit
end

branches_by_name = Branch.all.to_h { [_1.name, _1] }
Worktree.load_statuses(worktrees)
choices = worktrees.map { WorktreeChoice.new(_1, branches_by_name[_1.branch_name]) }.sort_by(&:sort_key)
selected_choice =
  SelectionPrompt.new(
    choices: choices,
    noun: "worktree",
    prompt_message: "Switch to a worktree:",
  ).prompt_for_selection

puts
if selected_choice.nil?
  # Cancelled
elsif selected_choice.current?
  puts "Already in #{ selected_choice.worktree.display_path }"
elsif selected_choice.worktree.missing?
  puts "#{ selected_choice.worktree.display_path } has been deleted. Run gsp to clean it up."
  exit(1)
else
  path_output.puts(selected_choice.worktree.path)
end
