require_relative "branch"
require_relative "prompt"
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

  # Asks again rather than silently ignoring a number that matches no branch.
  def prompt_for_branch_selection
    print_branches
    loop do
      print_input_prompt
      user_input = Prompt.read_line
      return if user_input.nil? || user_input.empty? || user_input.downcase == "c"

      branches, error = get_branches_from_user_input(user_input)
      if error
        puts Style.decorate(error, color: :red)
      elsif @allow_multiple
        return branches
      else
        return branches.first
      end
    end
  end

  # Returns the chosen branches, or an error message describing what was wrong.
  private def get_branches_from_user_input(user_input)
    branch_numbers = user_input.split(" ")
    if !@allow_multiple && branch_numbers.length > 1
      return [nil, "Type a single number."]
    end

    invalid_numbers = branch_numbers.reject { valid_branch_number?(_1) }
    if invalid_numbers.any?
      return [nil, "No branch numbered #{ invalid_numbers.join(", ") }."]
    end

    [branch_numbers.map { @branches[_1.to_i - 1] }.uniq, nil]
  end

  private def valid_branch_number?(branch_number)
    branch_number =~ NUMBER_REGEXP && branch_number.to_i.between?(1, @branches.length)
  end

  private def print_branches
    puts
    puts @prompt_message
    puts
    @branches.each.with_index(1) do |branch, position|
      position_string = position.to_s.rjust(3)
      position_color = branch.current? ? branch.recency_color : :cyan
      puts "#{ branch.indicator }#{ Style.decorate(position_string, color: position_color) } #{ branch.prompt_text }"
    end
    puts
  end

  private def print_input_prompt
    # Use print rather than puts so that the number(s) the user types shows on the same line
    if @allow_multiple
      print Style.decorate("Type the number(s) of the branch(es), type c to cancel: ")
    else
      print Style.decorate("Type the number of the branch, type c to cancel: ")
    end
  end
end
