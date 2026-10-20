require_relative "branch"
require_relative "style"

class BranchList
  def initialize(branches:)
    @branches = branches
  end

  def display
    puts
    @branches.each do |branch|
      indicator = branch.current? ? "*" : " "
      puts "#{ Style.decorate(indicator, color: :green) } #{ branch.prompt_text }"
    end
    puts
  end
end
