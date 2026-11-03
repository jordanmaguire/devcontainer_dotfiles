begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

require_relative "branch"

class BranchList
  def initialize(branches:)
    @branches = branches.sort_by { -_1.last_used_timestamp }
  end

  def display
    puts
    @branches.each do |branch|
      puts "#{ indicator(branch) } #{ branch.prompt_text }"
      puts "  #{ branch.worktree_text }" unless branch.worktree_text.empty?
    end
    puts
    # Key for the grey branch names, lined up with them
    if @branches.any?(&:no_upstream?)
      puts "  #{ decorate_string("no upstream", color: :light_black) }"
      puts
    end
  end

  # Mirrors `git branch`: * for the current branch, + for a branch checked out in another worktree
  private def indicator(branch)
    if branch.current?
      decorate_string("*", color: :green)
    elsif branch.in_other_worktree?
      decorate_string("+", color: :cyan)
    else
      " "
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
