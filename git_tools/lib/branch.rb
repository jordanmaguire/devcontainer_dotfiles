begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

require "open3"
require_relative "checkout_history"

class Branch
  SECONDS_IN_A_DAY = 86400
  # Roughly where `git log --date=relative` switches units: [below this many seconds, unit, seconds per unit]
  RELATIVE_TIME_UNITS = [
    [90, "second", 1],
    [90 * 60, "minute", 60],
    [36 * 3600, "hour", 3600],
    [14 * SECONDS_IN_A_DAY, "day", SECONDS_IN_A_DAY],
    [70 * SECONDS_IN_A_DAY, "week", 7 * SECONDS_IN_A_DAY],
    [365 * SECONDS_IN_A_DAY, "month", 30 * SECONDS_IN_A_DAY],
    [Float::INFINITY, "year", 365 * SECONDS_IN_A_DAY],
  ].freeze
  MAX_NAME_LENGTH = 50
  PROTECTED_BRANCH_NAMES = ["main", "master"].freeze

  def initialize(name, current: false, worktree_path: nil)
    @name = name
    @current = current
    @worktree_path = worktree_path
  end

  attr_reader :name, :worktree_path

  def protected?
    PROTECTED_BRANCH_NAMES.include?(@name)
  end

  def current?
    @current
  end

  # Checked out in a worktree other than the one we're in, so `git checkout` and `git branch -d`
  # will both refuse to touch it.
  def in_other_worktree?
    !current? && !@worktree_path.nil?
  end

  def recency_color
    time_color(last_used_timestamp)
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

    current? ? decorate_string(name_text, color: recency_color) : name_text
  end

  # When the branch was last checked out, falling back to its last commit for branches the reflogs
  # have no checkout of (e.g. one created with `git worktree add -b`). Branches sort by this, and
  # it's the time shown.
  def last_used_timestamp
    @last_used_timestamp ||= CheckoutHistory.timestamps[@name] || last_commit_timestamp || 0
  end

  private def time_suffix
    return "" if last_used_timestamp.zero?

    decorate_string(relative_time(last_used_timestamp), color: recency_color)
  end

  private def relative_time(timestamp)
    age_in_seconds = [Time.now.to_i - timestamp, 0].max
    _, unit, seconds_per_unit = RELATIVE_TIME_UNITS.find { |limit, _, _| age_in_seconds < limit }
    # Round to the nearest unit, as git does
    count = (age_in_seconds + seconds_per_unit / 2) / seconds_per_unit
    "#{ count } #{ unit }#{ "s" unless count == 1 } ago"
  end

  # Printed on its own line under the branch, indented by the caller to line up with the name
  def worktree_text
    return "" unless in_other_worktree?

    decorate_string(@worktree_path.sub(/\A#{Regexp.escape(Dir.home)}(?=\/|\z)/, "~"), color: :cyan)
  end

  private def unpushed_indicator
    unless has_upstream?
      return decorate_string("(no upstream)", color: :light_black)
    end

    unpushed_count = `git rev-list --count origin/#{ @name }..#{ @name } 2>/dev/null`.strip.to_i
    if unpushed_count > 0
      decorate_string("↑#{unpushed_count}", color: :magenta)
    else
      ""
    end
  end

  private def has_upstream?
    system("git rev-parse --abbrev-ref #{ @name }@{upstream} >/dev/null 2>&1")
  end

  private def last_commit_timestamp
    output = `git log -1 --format=%ct #{ @name } 2>/dev/null`.strip
    output.empty? ? nil : output.to_i
  end

  private def time_color(timestamp)
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

  private def decorate_string(string, color: :cyan)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end
end
