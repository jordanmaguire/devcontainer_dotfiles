#!/usr/bin/env ruby

require_relative "lib/branch_parser"
require_relative "lib/branch_list"

branches = BranchParser.new(`git branch`).branches
BranchList.new(branches:).display
