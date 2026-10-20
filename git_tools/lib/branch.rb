require_relative "git"
require_relative "style"

class Branch
  SECONDS_IN_A_DAY = 86400
  MAX_NAME_LENGTH = 50
  FIELDS = [
    "HEAD",
    "refname:short",
    "committerdate:unix",
    "committerdate:relative",
    "push:short",
    "push:track",
    "worktreepath",
  ].freeze

  # Every local branch, most recently committed first. One for-each-ref call replaces parsing
  # `git branch`, whose "+ " prefix for branches in other worktrees broke every tool, and the
  # three git calls each branch used to make for its age and push state.
  def self.all(merged: nil)
    args = ["for-each-ref", "--sort=-committerdate", "--format=#{ FIELDS.map { "%(#{ _1 })" }.join("%00") }"]
    args << "--merged=#{ merged }" if merged
    Git.run(*args, "refs/heads").stdout.each_line(chomp: true).map do |line|
      new(FIELDS.zip(line.split("\0", -1)).to_h)
    end
  end

  def initialize(fields)
    @current = fields["HEAD"] == "*"
    @name = fields["refname:short"]
    @timestamp = fields["committerdate:unix"].to_i
    @relative_time = fields["committerdate:relative"].to_s
    @push = fields["push:short"].to_s
    @push_track = fields["push:track"].to_s
    @worktree_path = fields["worktreepath"].to_s
  end

  attr_reader :name

  def protected?
    Git::PROTECTED_BRANCH_NAMES.include?(@name)
  end

  def current?
    @current
  end

  # Where the branch is checked out, if anywhere. Includes the current worktree.
  def worktree_path
    @worktree_path unless @worktree_path.empty?
  end

  def recency_color
    commit_time_color(@timestamp)
  end

  def last_commit_timestamp
    @timestamp
  end

  def prompt_text
    [truncated_name, time_suffix, unpushed_indicator].reject(&:empty?).join(" ")
  end

  private def truncated_name
    name_text = if @name.length > MAX_NAME_LENGTH
      @name[0, MAX_NAME_LENGTH - 1] + "…"
    else
      @name.ljust(MAX_NAME_LENGTH)
    end

    current? ? Style.decorate(name_text, color: recency_color) : name_text
  end

  private def time_suffix
    return "" if @relative_time.empty?

    Style.decorate(@relative_time, color: recency_color)
  end

  # Measured against where `git push` would send the branch, so a branch whose upstream is
  # origin/master is not reported as fully pushed.
  private def unpushed_indicator
    if @push.empty?
      Style.decorate("(no upstream)", color: :light_black)
    elsif @push_track == "[gone]"
      Style.decorate("(gone)", color: :light_black)
    elsif (unpushed_count = @push_track[/ahead (\d+)/, 1].to_i) > 0
      Style.decorate("↑#{ unpushed_count }", color: :magenta)
    else
      ""
    end
  end

  private def commit_time_color(timestamp)
    return :light_black if timestamp.zero?

    age_in_seconds = Time.now.to_i - timestamp
    if age_in_seconds < SECONDS_IN_A_DAY * 7
      :green
    elsif age_in_seconds < SECONDS_IN_A_DAY * 30
      :yellow
    else
      :light_black
    end
  end
end
