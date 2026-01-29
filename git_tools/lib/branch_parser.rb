require_relative "branch"

class BranchParser
  def initialize(git_branch_output)
    @git_branch_output = git_branch_output
  end

  def branches
    branch_names.map { Branch.new(_1) }
  end

  def current_branch_name
    @git_branch_output.split("\n").find { _1.start_with?("* ") }&.sub("* ", "")&.strip
  end

  private def branch_names
    @git_branch_output.gsub("* ", "").split("\n").map(&:strip)
  end
end
