require_relative "git"

# The ref a branch's work is measured against: the PR base the VS Code GitHub extension recorded
# for it, otherwise the remote's default branch. Remote refs win over local ones because a local
# master goes stale once you work in worktrees and never check it out to pull.
module BaseBranch
  module_function

  def for_branch(branch_name = current_branch_name)
    pr_base(branch_name) || default
  end

  def default
    origin_head = Git.read("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    return origin_head unless origin_head.empty?

    ["origin/main", "origin/master", "main", "master"].find { exists?(_1) } || "main"
  end

  def current_branch_name
    Git.read("symbolic-ref", "--quiet", "--short", "HEAD")
  end

  # Stored as "owner#repo#branch". A stacked PR's base may since have been merged and deleted.
  def pr_base(branch_name)
    return if branch_name.empty?

    base = Git.read("config", "--get", "branch.#{ branch_name }.github-pr-base-branch").split("#", 3).last
    return if base.nil? || base.empty?

    ["origin/#{ base }", base].find { exists?(_1) }
  end

  def exists?(ref)
    Git.ok?("rev-parse", "--verify", "--quiet", "#{ ref }^{commit}")
  end
end
