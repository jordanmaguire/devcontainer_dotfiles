# When each branch was last checked out, read from the HEAD reflog of every worktree in the repo
# (each worktree keeps its own).
module CheckoutHistory
  # How far back through each reflog to look for checkouts
  REFLOG_DEPTH = 1000

  # { "branch-name" => unix timestamp of its most recent checkout }
  def self.timestamps
    @timestamps ||= worktree_paths.each_with_object({}) do |path, timestamps|
      checkouts_in(path).each do |name, timestamp|
        timestamps[name] = timestamp if timestamp > timestamps.fetch(name, 0)
      end
    end
  end

  private_class_method def self.worktree_paths
    `git worktree list --porcelain -z 2>/dev/null`
      .split("\0")
      .filter_map { _1.delete_prefix("worktree ") if _1.start_with?("worktree ") }
  end

  # With --date=unix, %gd comes out as HEAD@{<timestamp>}
  private_class_method def self.checkouts_in(path)
    output, = Open3.capture2(
      "git", "-C", path, "reflog", "-n", REFLOG_DEPTH.to_s, "--date=unix", "--format=%gd%x00%gs",
      err: File::NULL,
    )
    output.each_line.filter_map do |line|
      selector, subject = line.chomp.split("\0", 2)
      name = subject.to_s[/\Acheckout: moving from \S+ to (\S+)\z/, 1]
      timestamp = selector[/\{(\d+)\}/, 1]
      [name, timestamp.to_i] if name && timestamp
    end
  end
end
