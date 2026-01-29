begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

class BranchSelectionPrompt::Branch
  SECONDS_IN_A_DAY = 86400

  def initialize(name)
    @name = name
  end

  attr_reader :name

  def prompt_text
    "#{ @name }#{ time_suffix }"
  end

  def last_commit_timestamp
    last_commit_info.first || 0
  end

  private def time_suffix
    timestamp, relative_time = last_commit_info
    return "" if relative_time.empty?

    " (#{decorate_string(relative_time, color: commit_time_color(timestamp))})"
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
