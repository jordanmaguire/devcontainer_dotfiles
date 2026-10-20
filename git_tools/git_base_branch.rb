#!/usr/bin/env ruby

# Prints the ref the current branch is measured against, for use in aliases.
require_relative "lib/base_branch"

puts BaseBranch.for_branch
