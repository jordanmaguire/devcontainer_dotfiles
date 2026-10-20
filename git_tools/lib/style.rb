begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

module Style
  module_function

  def decorate(string, color: :cyan)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end
end
