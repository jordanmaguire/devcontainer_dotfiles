require_relative "branch"
require_relative "style"

class BranchSelectionPrompt
  NUMBER_REGEXP = /\A\d+\z/

  def initialize(allow_multiple: false, branches:, exclude_protected_branches: false, prompt_message:)
    @allow_multiple = allow_multiple
    @branches = branches
    if exclude_protected_branches
      @branches = @branches.reject(&:protected?)
    end
    @prompt_message = Style.decorate(prompt_message)
  end

  def prompt_for_branch_selection
    print_prompt_for_branch_selection
    get_branch_name_from_user_input(gets.strip)
  end

  private def get_branch_name_from_user_input(user_input)
    return if user_input.downcase == "c"

    branch_numbers = user_input.split(" ")
    branch_names = branch_numbers.map do |branch_number|
      if branch_number =~ NUMBER_REGEXP
        chosen_branch_index = branch_number.to_i - 1
        if chosen_branch_index != -1 && !(chosen_branch = @branches[chosen_branch_index]).nil?
          chosen_branch.name
        end
      end
    end.compact

    if @allow_multiple
      branch_names
    else
      branch_names.first
    end
  end

  private def print_prompt_for_branch_selection
    puts
    puts @prompt_message
    puts
    @branches.each.with_index(1) do |branch, position|
      position_string = position.to_s.rjust(3)
      position_color = branch.current? ? branch.recency_color : :cyan
      current_indicator = branch.current? ? Style.decorate("*", color: branch.recency_color) : " "
      puts "#{ current_indicator }#{ Style.decorate(position_string, color: position_color) } #{ branch.prompt_text }"
    end
    puts

    # Use print rather than puts so that the number(s) the user types shows on the same line
    if @allow_multiple
      print Style.decorate("Type the number(s) of the branch(es), type c to cancel: ")
    else
      print Style.decorate("Type the number of the branch, type c to cancel: ")
    end
  end
end
