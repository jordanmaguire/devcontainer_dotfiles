class BranchParser
  def initialize(git_branch_output)
    @git_branch_output = git_branch_output
  end

  def branches
    @git_branch_output.gsub("* ", "").split("\n").map(&:strip)
  end

  def current_branch
    @git_branch_output.split("\n").find { _1.start_with?("* ") }&.sub("* ", "")&.strip
  end
end
