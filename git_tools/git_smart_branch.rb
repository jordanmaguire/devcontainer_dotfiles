#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_list"

parser = BranchParser.new(`git branch`)
BranchList.new(
  branches: parser.branches,
  current_branch_name: parser.current_branch_name,
).display
