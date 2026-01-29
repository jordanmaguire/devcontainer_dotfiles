begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

class BranchSelectionPrompt
  NUMBER_REGEXP = /\A\d+\z/

  def initialize(allow_multiple: false, branches:, exclude_protected_branches: false, prompt_message:)
    @allow_multiple = allow_multiple
    @branches = branches
    if exclude_protected_branches
      @branches = @branches.reject { ["main", "master"].include?(_1) }
    end
    @exclude_protected_branches = exclude_protected_branches
    @prompt_message = decorate_string(prompt_message)
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
        if chosen_branch_index != -1 && !(chosen_branch_name = @branches[chosen_branch_index]).nil?
          chosen_branch_name
        end
      end
    end.compact

    if @allow_multiple
      branch_names
    else
      branch_names.first
    end
  end

  private def decorate_string(string, color: :cyan)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end

  SECONDS_IN_A_DAY = 86400

  private def last_commit_info(branch_name)
    output = `git log -1 --format="%ct|%cr" #{ branch_name } 2>/dev/null`.strip
    return [nil, ""] if output.empty?

    timestamp, relative_time = output.split("|", 2)
    [timestamp.to_i, relative_time]
  end

  private def commit_time_color(timestamp)
    return :light_black if timestamp.nil?

    age_in_seconds = Time.now.to_i - timestamp
    if age_in_seconds < SECONDS_IN_A_DAY
      :green
    elsif age_in_seconds < SECONDS_IN_A_DAY * 7
      :yellow
    else
      :light_black
    end
  end

  private def print_prompt_for_branch_selection
    puts
    puts @prompt_message
    puts
    @branches.each.with_index(1) do |branch_name, position|
      position_string = position.to_s.rjust(3)
      timestamp, relative_time = last_commit_info(branch_name)
      time_suffix = relative_time.empty? ? "" : " (#{decorate_string(relative_time, color: commit_time_color(timestamp))})"
      puts "#{ decorate_string(position_string) } #{ branch_name }#{ time_suffix }"
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
