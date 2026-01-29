begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

class Branch
  SECONDS_IN_A_DAY = 86400
  MAX_NAME_LENGTH = 50
  PROTECTED_BRANCH_NAMES = ["main", "master"].freeze

  def initialize(name, current: false)
    @name = name
    @current = current
  end

  attr_reader :name

  def protected?
    PROTECTED_BRANCH_NAMES.include?(@name)
  end

  def current?
    @current
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

    current? ? decorate_string(name_text, color: commit_time_color(last_commit_info.first)) : name_text
  end

  def last_commit_timestamp
    last_commit_info.first || 0
  end

  private def time_suffix
    timestamp, relative_time = last_commit_info
    return "" if relative_time.empty?

    decorate_string(relative_time, color: commit_time_color(timestamp))
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

  private def last_commit_info
    @last_commit_info ||= begin
      output = `git log -1 --format="%ct|%cr" #{ @name } 2>/dev/null`.strip
      if output.empty?
        [nil, ""]
      else
        timestamp, relative_time = output.split("|", 2)
        [timestamp.to_i, relative_time]
      end
    end
  end

  private def commit_time_color(timestamp)
    return :light_black if timestamp.nil?

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
