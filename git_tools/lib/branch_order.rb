# The few most recently checked out branches first (newest first), then the rest by last commit.
module BranchOrder
  RECENT_CHECKOUT_COUNT = 5
  # How far back through the reflog to look for checkouts
  REFLOG_DEPTH = 1000

  def self.sort(branches)
    by_last_commit = branches.sort_by { -_1.last_commit_timestamp }
    branches_by_name = by_last_commit.to_h { [_1.name, _1] }

    recently_checked_out = recent_checkout_names
      .filter_map { branches_by_name[_1] }
      .first(RECENT_CHECKOUT_COUNT)

    recently_checked_out + (by_last_commit - recently_checked_out)
  end

  # Branch names from this worktree's HEAD reflog, most recent first. Checkouts made in other
  # worktrees live in their own reflogs and aren't seen here.
  def self.recent_checkout_names
    `git reflog -n #{ REFLOG_DEPTH } --format=%gs 2>/dev/null`
      .each_line
      .filter_map { _1[/\Acheckout: moving from \S+ to (\S+)$/, 1] }
      .uniq
  end
end
