module Prompt
  module_function

  # The user's answer, or nil when they cancel with Ctrl-C or Ctrl-D. Reads $stdin rather than
  # Kernel#gets, which would read from a file if the script was given arguments.
  def read_line
    line = $stdin.gets
    puts if line.nil?
    line&.strip
  rescue Interrupt
    puts
    nil
  end

  def confirm?(message)
    # Use print rather than puts so that what the user types shows on the same line
    print "#{ message } "
    read_line == "y"
  end
end
