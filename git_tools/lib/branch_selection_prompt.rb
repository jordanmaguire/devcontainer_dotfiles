begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

require_relative "branch"

class BranchSelectionPrompt
  NUMBER_REGEXP = /\A\d+\z/

  def initialize(allow_multiple: false, branches:, exclude_protected_branches: false, prompt_message:)
    @allow_multiple = allow_multiple
    @branches = branches
    if exclude_protected_branches
      @branches = @branches.reject(&:protected?)
    end
    @branches = @branches.sort_by { -_1.last_commit_timestamp }
    @prompt_message = decorate_string(prompt_message)
  end

  def prompt_for_branch_selection
    print_prompt_for_branch_selection
    get_branches_from_user_input(gets.strip)
  end

  private def get_branches_from_user_input(user_input)
    return if user_input.downcase == "c"

    branch_numbers = user_input.split(" ")
    chosen_branches = branch_numbers.map do |branch_number|
      if branch_number =~ NUMBER_REGEXP
        chosen_branch_index = branch_number.to_i - 1
        if chosen_branch_index != -1
          @branches[chosen_branch_index]
        end
      end
    end.compact

    if @allow_multiple
      chosen_branches
    else
      chosen_branches.first
    end
  end

  private def decorate_string(string, color: :cyan)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end

  # Mirrors `git branch`: * for the current branch, + for a branch checked out in another worktree
  private def indicator(branch)
    if branch.current?
      decorate_string("*", color: branch.recency_color)
    elsif branch.in_other_worktree?
      decorate_string("+", color: :cyan)
    else
      " "
    end
  end

  private def print_prompt_for_branch_selection
    puts
    puts @prompt_message
    puts
    @branches.each.with_index(1) do |branch, position|
      position_string = position.to_s.rjust(3)
      position_color = branch.current? ? branch.recency_color : :cyan
      puts "#{ indicator(branch) }#{ decorate_string(position_string, color: position_color) } #{ branch.prompt_text }"
    end
    puts

    # Use print rather than puts so that the number(s) the user types shows on the same line
    if @allow_multiple
      print decorate_string("Type the number(s) of the branch(es), type c to cancel: ")
    else
      print decorate_string("Type the number of the branch, type c to cancel: ")
    end
  end
end
