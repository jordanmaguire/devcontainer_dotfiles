require_relative "branch"

class BranchList
  def initialize(branches:)
    @branches = branches
  end

  def display
    puts
    @branches.each do |branch|
      puts "#{ branch.indicator } #{ branch.prompt_text }"
    end
    puts
  end
end
