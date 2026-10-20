require_relative "prompt"
require_relative "style"

# Lists numbered choices and returns the one(s) picked. A choice responds to indicator,
# prompt_text, current? and recency_color, as Branch does.
class SelectionPrompt
  NUMBER_REGEXP = /\A\d+\z/

  def initialize(allow_multiple: false, choices:, noun:, plural_noun: "#{ noun }s", prompt_message:)
    @allow_multiple = allow_multiple
    @choices = choices
    @noun = noun
    @plural_noun = plural_noun
    @prompt_message = Style.decorate(prompt_message)
  end

  # Asks again rather than silently ignoring a number that matches no choice.
  def prompt_for_selection
    print_choices
    loop do
      print_input_prompt
      user_input = Prompt.read_line
      return if user_input.nil? || user_input.empty? || user_input.downcase == "c"

      choices, error = get_choices_from_user_input(user_input)
      if error
        puts Style.decorate(error, color: :red)
      elsif @allow_multiple
        return choices
      else
        return choices.first
      end
    end
  end

  # Returns the chosen choices, or an error message describing what was wrong.
  private def get_choices_from_user_input(user_input)
    numbers = user_input.split(" ")
    if !@allow_multiple && numbers.length > 1
      return [nil, "Type a single number."]
    end

    invalid_numbers = numbers.reject { valid_number?(_1) }
    if invalid_numbers.any?
      return [nil, "No #{ @noun } numbered #{ invalid_numbers.join(", ") }."]
    end

    [numbers.map { @choices[_1.to_i - 1] }.uniq, nil]
  end

  private def valid_number?(number)
    number =~ NUMBER_REGEXP && number.to_i.between?(1, @choices.length)
  end

  private def print_choices
    puts
    puts @prompt_message
    puts
    @choices.each.with_index(1) do |choice, position|
      position_string = position.to_s.rjust(3)
      position_color = choice.current? ? choice.recency_color : :cyan
      puts "#{ choice.indicator }#{ Style.decorate(position_string, color: position_color) } #{ choice.prompt_text }"
    end
    puts
  end

  private def print_input_prompt
    # Use print rather than puts so that the number(s) the user types shows on the same line
    if @allow_multiple
      print Style.decorate("Type the number(s) of the #{ @plural_noun }, type c to cancel: ")
    else
      print Style.decorate("Type the number of the #{ @noun }, type c to cancel: ")
    end
  end
end
