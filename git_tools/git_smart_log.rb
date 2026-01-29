#!/usr/bin/env ruby

begin
  require "colorize"
rescue LoadError
  # Oh well, we tried.
end

class CommitLog
  def initialize
    @base_branch = detect_base_branch
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

  def detect_base_branch
    %w[main master].find { |branch| branch_exists?(branch) } || "main"
  end

  def branch_exists?(branch)
    system("git rev-parse --verify #{branch} >/dev/null 2>&1")
  end

  def branch_commits
    `git log #{@base_branch}..HEAD --format="%h|%cr|%s" 2>/dev/null`.strip.split("\n").reject(&:empty?)
  end

  def display_commit(commit_line)
    sha, time, message = commit_line.split("|", 3)

    puts "#{decorate(sha, :yellow)} #{decorate(time, :green)} #{decorate(message, :cyan)}"
    puts diff_stat(sha)
    puts
  end

  def diff_stat(sha)
    raw_stat = `git diff --stat #{sha}^..#{sha} 2>/dev/null`.strip
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
    stats.gsub(/\+/) { decorate("+", :green) }.gsub(/-/) { decorate("-", :red) }
  end

  def colorize_summary(summary)
    summary
      .gsub(/(\d+) insertion(s?)/) { "#{decorate($1, :green)} insertion#{$2}" }
      .gsub(/(\d+) deletion(s?)/) { "#{decorate($1, :red)} deletion#{$2}" }
  end

  def decorate(string, color)
    if string.respond_to?(color)
      string.send(color)
    else
      string
    end
  end
end

CommitLog.new.display
