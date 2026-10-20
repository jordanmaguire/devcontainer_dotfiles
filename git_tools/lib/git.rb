require "open3"

# Runs git with an argument array rather than a shell string, so branch names are never
# interpreted by a shell and failures can be reported instead of silently swallowed.
module Git
  PROTECTED_BRANCH_NAMES = ["main", "master"].freeze

  class Result
    def initialize(stdout, stderr, status)
      @stdout = stdout
      @stderr = stderr
      @status = status
    end

    attr_reader :stdout, :stderr

    def success?
      @status.success?
    end

    # git writes its useful failure message to stderr, but some commands use stdout.
    def message
      [@stderr, @stdout].map(&:strip).reject(&:empty?).first.to_s
    end
  end

  module_function

  def run(*args)
    Result.new(*Open3.capture3("git", *args))
  end

  # The stripped output of a command, or "" when it fails.
  def read(*args)
    result = run(*args)
    result.success? ? result.stdout.strip : ""
  end

  def ok?(*args)
    run(*args).success?
  end
end
