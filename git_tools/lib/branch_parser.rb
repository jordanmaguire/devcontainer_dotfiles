require_relative "branch"

# Parses the output of `git branch --format="#{BranchParser::FORMAT}"`. Plain `git branch` output
# can't tell us where a branch is checked out, which matters once worktrees are in play.
class BranchParser
  # %(HEAD) is "*" for the branch checked out in the current worktree, %(worktreepath) is the
  # path of whichever worktree has the branch checked out (blank if none). NUL separated because
  # both paths and branch names can contain pretty much anything else.
  FORMAT = "%(HEAD)%00%(worktreepath)%00%(refname:short)"

  def initialize(git_branch_output)
    @git_branch_output = git_branch_output
  end

  def branches
    @git_branch_output.split("\n").filter_map do |line|
      head, worktree_path, name = line.split("\0", 3)
      # A detached HEAD shows up as "(no branch)" or "(HEAD detached at …)"
      next if name.nil? || name.start_with?("(")

      Branch.new(
        name,
        current: head == "*",
        worktree_path: worktree_path.empty? ? nil : worktree_path,
      )
    end
  end
end
