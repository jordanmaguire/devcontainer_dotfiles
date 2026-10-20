#!/usr/bin/env ruby

require_relative "lib/base_branch"
require_relative "lib/git"
require_relative "lib/style"

class CommitLog
  def initialize
    @base_branch = BaseBranch.for_branch
  end

  def display
    commits = branch_commits
    if commits.empty?
      puts "No commits on this branch (or already merged with #{@base_branch})"
      return
    end

    puts
    commits.each do |commit|
      display_commit(commit)
    end
  end

  private

  def branch_commits
    Git.read("log", "#{@base_branch}..HEAD", "--format=%h|%cr|%s").split("\n").reject(&:empty?)
  end

  def display_commit(commit_line)
    sha, time, message = commit_line.split("|", 3)

    puts "#{Style.decorate(sha, color: :yellow)} #{Style.decorate(time, color: :green)} #{Style.decorate(message, color: :cyan)}"
    puts diff_stat(sha)
    puts
  end

  def diff_stat(sha)
    raw_stat = Git.read("diff", "--stat", "#{sha}^..#{sha}")
    align_diff_stat(raw_stat)
  end

  def align_diff_stat(raw_stat)
    lines = raw_stat.split("\n")
    return raw_stat if lines.empty?

    # Separate file lines from summary line
    summary_line = lines.last
    file_lines = lines[0..-2]

    return raw_stat if file_lines.empty?

    # Parse file lines to find max path length
    parsed = file_lines.map do |line|
      if line =~ /^(.+?)\s*\|\s*(.+)$/
        [$1.strip, $2]
      else
        nil
      end
    end.compact

    return raw_stat if parsed.empty?

    max_path_length = parsed.map { _1[0].length }.max

    # Rebuild with aligned pipes and colorized stats
    aligned = parsed.map do |path, stats|
      " #{path.ljust(max_path_length)} | #{colorize_stats(stats)}"
    end

    (aligned + [colorize_summary(summary_line)]).join("\n")
  end

  def colorize_stats(stats)
    stats.gsub(/\+/) { Style.decorate("+", color: :green) }.gsub(/-/) { Style.decorate("-", color: :red) }
  end

  def colorize_summary(summary)
    summary
      .gsub(/(\d+) insertion(s?)/) { "#{Style.decorate($1, color: :green)} insertion#{$2}" }
      .gsub(/(\d+) deletion(s?)/) { "#{Style.decorate($1, color: :red)} deletion#{$2}" }
  end
end

CommitLog.new.display
