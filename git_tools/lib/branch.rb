require_relative "git"
require_relative "style"
require_relative "worktree"

class Branch
  SECONDS_IN_A_DAY = 86400
  MAX_NAME_LENGTH = 50
  FIELDS = [
    "HEAD",
    "refname",
    "refname:short",
    "committerdate:unix",
    "committerdate:relative",
    "push:short",
    "push:track",
    "upstream:track",
    "worktreepath",
  ].freeze

  # Every local branch, most recently committed first. One for-each-ref call replaces parsing
  # `git branch`, whose "+ " prefix for branches in other worktrees broke every tool, and the
  # three git calls each branch used to make for its age and push state.
  def self.all(merged: nil, refs: "refs/heads")
    worktrees_by_path = Worktree.all.to_h { [_1.path, _1] }
    args = ["for-each-ref", "--sort=-committerdate", "--format=#{ FIELDS.map { "%(#{ _1 })" }.join("%00") }"]
    args << "--merged=#{ merged }" if merged
    branches = Git.run(*args, refs).stdout.each_line(chomp: true).map do |line|
      fields = FIELDS.zip(line.split("\0", -1)).to_h
      new(fields, worktree: worktrees_by_path[fields["worktreepath"]])
    end
    Worktree.load_statuses(branches.select(&:checked_out_elsewhere?).map(&:worktree))
    branches
  end

  def initialize(fields, worktree: nil)
    @current = fields["HEAD"] == "*"
    @remote = fields["refname"].to_s.start_with?("refs/remotes/")
    @name = fields["refname:short"]
    @timestamp = fields["committerdate:unix"].to_i
    @relative_time = fields["committerdate:relative"].to_s
    @push = fields["push:short"].to_s
    @push_track = fields["push:track"].to_s
    @upstream_track = fields["upstream:track"].to_s
    @worktree = worktree
  end

  # The worktree the branch is checked out in, if any. Includes the current one.
  attr_reader :name, :worktree

  def protected?
    Git::PROTECTED_BRANCH_NAMES.include?(@name)
  end

  def current?
    @current
  end

  # The remote branch was deleted, which usually means its PR was merged, perhaps by squashing,
  # which `--merged` cannot detect.
  def upstream_gone?
    @upstream_track == "[gone]"
  end

  # git refuses to check out or delete a branch that another worktree has checked out.
  def checked_out_elsewhere?
    !@worktree.nil? && !current?
  end

  # Marks the current branch with *, and branches in other worktrees with + as `git branch` does.
  def indicator
    if current?
      Style.decorate("*", color: recency_color)
    elsif checked_out_elsewhere?
      Style.decorate("+", color: :blue)
    else
      " "
    end
  end

  def recency_color
    commit_time_color(@timestamp)
  end

  def last_commit_timestamp
    @timestamp
  end

  def prompt_text(show_worktree: checked_out_elsewhere?)
    worktree_text = show_worktree && @worktree ? @worktree.status_text : ""
    [truncated_name, time_suffix, unpushed_indicator, worktree_text].reject(&:empty?).join(" ")
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
    if @remote
      ""
    elsif @push.empty?
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
