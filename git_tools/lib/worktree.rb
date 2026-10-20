require_relative "git"
require_relative "style"

class Worktree
  # Parsed from `git worktree list --porcelain`, whose first entry is always the main worktree.
  def self.all
    current_path = real_path(Git.read("rev-parse", "--show-toplevel"))
    entries = Git.read("worktree", "list", "--porcelain").split("\n\n")
    entries.map.with_index do |entry, index|
      # Lines are "key value", or a bare key such as "detached" or a "locked" with no reason.
      attributes = entry.split("\n").to_h { |line| key, value = line.split(" ", 2); [key, value] }
      new(attributes, main: index.zero?, current: real_path(attributes["worktree"]) == current_path)
    end
  end

  # Fetches the status of several worktrees in parallel. Each `git status` can take a noticeable
  # fraction of a second in a large repo.
  def self.load_statuses(worktrees)
    worktrees.map { |worktree| Thread.new { worktree.status } }.each(&:join)
  end

  def self.main_path
    @main_path ||= File.dirname(Git.read("rev-parse", "--path-format=absolute", "--git-common-dir"))
  end

  def self.real_path(path)
    File.realpath(path)
  rescue SystemCallError
    path
  end

  def initialize(attributes, main:, current:)
    @path = attributes["worktree"]
    @head = attributes["HEAD"].to_s
    @branch_name = attributes["branch"]&.delete_prefix("refs/heads/")
    @locked = attributes.key?("locked")
    @lock_reason = attributes["locked"]
    @prunable = attributes.key?("prunable")
    @main = main
    @current = current
  end

  attr_reader :path, :head, :branch_name, :lock_reason

  def main?
    @main
  end

  def current?
    @current
  end

  def locked?
    @locked
  end

  # The folder was deleted without `git worktree remove`.
  def missing?
    @prunable || !Dir.exist?(@path)
  end

  def detached?
    @branch_name.nil?
  end

  # :clean, :modified (tracked changes), :untracked (only untracked files) or :missing.
  # `git worktree remove` refuses anything but :clean without --force.
  def status
    @status ||= if missing?
      :missing
    else
      lines = Git.read("-C", @path, "status", "--porcelain").split("\n")
      if lines.empty?
        :clean
      elsif lines.all? { _1.start_with?("??") }
        :untracked
      else
        :modified
      end
    end
  end

  def clean?
    status == :clean
  end

  # Relative to the main worktree when inside it, otherwise absolute with ~ for home.
  def display_path
    main_path = self.class.main_path
    if !main? && @path.start_with?("#{ main_path }/")
      @path.delete_prefix("#{ main_path }/")
    else
      @path.sub(/\A#{ Regexp.escape(Dir.home) }(?=\/|\z)/, "~")
    end
  end

  # Shown next to a branch or worktree in the tools' listings.
  def status_text
    texts = []
    texts << Style.decorate(display_path, color: :blue)
    case status
    when :modified then texts << Style.decorate("(modified)", color: :yellow)
    when :untracked then texts << Style.decorate("(untracked files)", color: :light_black)
    when :missing then texts << Style.decorate("(folder missing)", color: :red)
    end
    texts << Style.decorate("(locked)", color: :light_black) if locked?
    texts.join(" ")
  end
end
