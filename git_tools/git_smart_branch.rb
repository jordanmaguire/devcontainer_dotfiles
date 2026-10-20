#!/usr/bin/env ruby

require_relative "lib/branch"
require_relative "lib/branch_list"
require_relative "lib/git"

branches = Branch.all
BranchList.new(branches:).display
