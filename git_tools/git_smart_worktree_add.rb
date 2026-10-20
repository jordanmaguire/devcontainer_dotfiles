#!/usr/bin/env ruby

# Usage: gwt [branch]
#
# Creates a worktree for a branch and cds into it: an existing local branch, a branch that only
# exists on origin, or a new branch started from origin's default branch. With no branch given,
# offers the local branches not checked out anywhere.
#
# Configure with git config:
#   smarttools.worktreeRoot  Where worktrees go, relative to the main worktree. Default .claude/worktrees
#   smarttools.worktreeCopy  Glob of gitignored files to copy from the main worktree, such as
#                            app/.env. May be given more than once. Default **/.env

require "fileutils"
require_relative "lib/base_branch"
require_relative "lib/branch"
require_relative "lib/git"
require_relative "lib/selection_prompt"
require_relative "lib/worktree"

DEFAULT_ROOT = ".claude/worktrees"
DEFAULT_COPY_PATTERNS = ["**/.env"].freeze
# Dependency folders can hold their own .env files, and are slow to search.
COPY_EXCLUDE_PATTERNS = ["**/node_modules/**", "**/vendor/**"].freeze

class WorktreeCreator
  def initialize(branch_name)
    @branch_name = branch_name
    @main_path = Worktree.main_path
    @root = File.expand_path(Git.read("config", "--get", "smarttools.worktreeRoot").then { _1.empty? ? DEFAULT_ROOT : _1 }, @main_path)
    @path = File.join(@root, branch_name.tr("/", "-"))
  end

  # Returns the new worktree's path, or nil when it could not be created.
  def create
    if File.exist?(@path)
      puts "#{ display_path } already exists."
      return
    end

    result =
      if Git.ok?("show-ref", "--verify", "--quiet", "refs/heads/#{ @branch_name }")
        add_existing_branch
      elsif Git.ok?("show-ref", "--verify", "--quiet", "refs/remotes/origin/#{ @branch_name }")
        add_remote_branch
      else
        add_new_branch
      end
    unless result.success?
      puts result.message
      return
    end

    exclude_root_from_main_worktree
    copy_ignored_files
    @path
  end

  private def add_existing_branch
    puts "Checking out #{ @branch_name } in #{ display_path }"
    Git.run("worktree", "add", @path, @branch_name)
  end

  private def add_remote_branch
    puts "Checking out #{ @branch_name } from origin in #{ display_path }"
    Git.run("worktree", "add", "--track", "-b", @branch_name, @path, "origin/#{ @branch_name }")
  end

  # --no-track because a branch started from origin/master would otherwise track it, and with
  # push.default=upstream a plain `git push` would then push to master.
  private def add_new_branch
    base_branch = BaseBranch.default
    fetch_base_branch(base_branch)
    puts "Creating #{ @branch_name } from #{ base_branch } in #{ display_path }"
    Git.run("worktree", "add", "--no-track", "-b", @branch_name, @path, base_branch)
  end

  private def fetch_base_branch(base_branch)
    remote, branch = base_branch.split("/", 2)
    return unless remote == "origin" && branch

    puts "Fetching #{ base_branch }…"
    result = Git.run("fetch", "origin", branch)
    puts "  Could not fetch, so starting from the last fetched #{ base_branch }: #{ result.message }" unless result.success?
  end

  # A worktree inside the main worktree shows up there as untracked unless it is ignored.
  private def exclude_root_from_main_worktree
    return unless @root.start_with?("#{ @main_path }/")
    return if Git.ok?("-C", @main_path, "check-ignore", "--quiet", @path)

    exclude_file = File.join(Git.read("rev-parse", "--path-format=absolute", "--git-common-dir"), "info", "exclude")
    FileUtils.mkdir_p(File.dirname(exclude_file))
    File.open(exclude_file, "a") { _1.puts("/#{ @root.delete_prefix("#{ @main_path }/") }/") }
    puts "Added #{ @root.delete_prefix("#{ @main_path }/") } to #{ exclude_file }"
  end

  # Untracked setup such as .env files is not part of a checkout, so a new worktree lacks it.
  private def copy_ignored_files
    patterns = Git.read("config", "--get-all", "smarttools.worktreeCopy").split("\n")
    patterns = DEFAULT_COPY_PATTERNS if patterns.empty?
    pathspecs = patterns.map { ":(glob)#{ _1 }" } + COPY_EXCLUDE_PATTERNS.map { ":(exclude,glob)#{ _1 }" }
    files = Git.read("-C", @main_path, "ls-files", "--others", "--ignored", "--exclude-standard", "--", *pathspecs).split("\n")

    copied = files.filter_map do |file|
      source = File.join(@main_path, file)
      destination = File.join(@path, file)
      next if source.start_with?("#{ @root }/") || File.exist?(destination)

      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination, preserve: true)
      file
    end
    puts "Copied #{ copied.join(", ") } from the main worktree" if copied.any?
  end

  private def display_path
    @path.start_with?("#{ @main_path }/") ? @path.delete_prefix("#{ @main_path }/") : @path
  end
end

# The gwt shell function cds into whatever this prints, so everything else goes to stderr.
path_output = $stdout
$stdout = $stderr

branch_name = ARGV.first
if branch_name.nil?
  branches = Branch.all.reject(&:worktree)
  if branches.empty?
    puts "Every branch is already checked out. Give a name to create a new one: gwt <branch>"
    exit
  end

  selected_branch =
    SelectionPrompt.new(
      choices: branches,
      noun: "branch",
      plural_noun: "branches",
      prompt_message: "Create a worktree for a branch:",
    ).prompt_for_selection
  exit if selected_branch.nil?

  puts
  branch_name = selected_branch.name
end

unless Git.ok?("check-ref-format", "--branch", branch_name)
  puts "#{ branch_name } is not a valid branch name."
  exit(1)
end

existing = Branch.all.find { _1.name == branch_name && _1.worktree }
if existing&.current?
  puts "Already on #{ branch_name }"
elsif existing
  puts "#{ branch_name } is already checked out in #{ existing.worktree.display_path }"
  path_output.puts(existing.worktree.path)
elsif (path = WorktreeCreator.new(branch_name).create)
  path_output.puts(path)
else
  exit(1)
end
