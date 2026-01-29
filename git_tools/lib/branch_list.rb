begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

require_relative "branch"

class BranchList
  def initialize(branches:)
    @branches = branches.sort_by { -_1.last_commit_timestamp }
  end

  def display
    puts
    @branches.each do |branch|
      indicator = branch.current? ? "*" : " "
      puts "#{ decorate_string(indicator, color: :green) } #{ branch.prompt_text }"
    end
    puts
  end

  private def decorate_string(string, color: :cyan)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end
end
