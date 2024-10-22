class BranchParser
  def initialize(git_branch_output)
    @git_branch_output = git_branch_output
  end

  def branches
    @git_branch_output.gsub("* ", "").split("\n").map(&:strip)
  end
end
