#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_list"
require_relative "lib/git"

branches = BranchParser.new(Git.read("branch")).branches
BranchList.new(branches:).display
