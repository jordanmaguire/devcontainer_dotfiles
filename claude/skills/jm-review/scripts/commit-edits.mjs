#!/usr/bin/env node
// Commits one group of review edits, and nothing else, as a fixup or a new commit.
//
// Reads JSON on stdin:
//   { "fixup": "<sha>" | "message": "<subject>\n\n<body>", "edits": [{ file, line, before, after, context_after? }] }
// and, run from inside the repository:
//   1. checks nothing is staged, so the commit can only hold these edits;
//   2. makes each edit in both the working tree and the index, so other uncommitted work in the same files stays out
//      of the commit and stays in the working tree;
//   3. commits the index (`git commit --fixup=<sha>` or `git commit -F -`).
//
// `before` and `context_after` are matched as whole lines. Where they occur more than once, the occurrence nearest
// `line` in the working tree is taken, and the same occurrence (by count from the top) in the index.
//
// --check works everything out and writes nothing.
//
// Prints one JSON line: { "ok": true, "commit": "<short sha>", "subject": "..." } or { "ok": false, "error": "..." },
// and exits 1 on an error. Nothing is written unless every edit in the group can be made.
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const isCheck = process.argv.includes('--check')

const git = (args, input) =>
  execFileSync('git', args, { encoding: 'utf8', input, stdio: ['pipe', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 })

const fail = error => {
  process.stdout.write(`${JSON.stringify({ ok: false, error })}\n`)
  process.exit(1)
}

const lines = text => (text === '' ? [] : text.replace(/\r/g, '').replace(/\n$/, '').split('\n'))

// Indexes where `run` starts as whole lines of `content` (compared without a trailing \r).
const occurrences = (content, run) => {
  const found = []
  for (let start = 0; start + run.length <= content.length; start++)
    if (run.every((line, offset) => content[start + offset].replace(/\r$/, '') === line)) found.push(start)
  return found
}

const nearest = (found, line) =>
  found.reduce((best, start) => (Math.abs(start - (line - 1)) < Math.abs(best - (line - 1)) ? start : best))

// Where the edit applies in each copy: the start of `before` (or, for a pure insertion, of `context_after`), as an
// ordinal shared by the working tree and the index.
const locate = (edit, tree, index, file) => {
  const anchor = lines(edit.before).length > 0 ? lines(edit.before) : lines(edit.context_after ?? '')
  if (anchor.length === 0) return { tree: edit.line - 1, index: edit.line - 1 }

  const what = lines(edit.before).length > 0 ? '`before`' : '`context_after`'
  const inTree = occurrences(tree, anchor)
  const inIndex = occurrences(index, anchor)
  if (inTree.length === 0) fail(`${file}:${edit.line}: ${what} is not in the working tree as whole lines`)
  if (inIndex.length === 0)
    fail(`${file}:${edit.line}: ${what} is only in uncommitted work, not in the index; leave this change uncommitted`)
  if (inTree.length !== inIndex.length)
    fail(`${file}:${edit.line}: ${what} occurs ${inTree.length} times in the working tree but ${inIndex.length} in the index`)
  const start = nearest(inTree, edit.line)

  return { tree: start, index: inIndex[inTree.indexOf(start)] }
}

const splice = (content, start, edit) => {
  const removed = lines(edit.before).length
  const eol = content[start]?.endsWith('\r') ? '\r' : ''
  content.splice(start, removed, ...lines(edit.after).map(line => line + eol))
}

let input
try {
  input = JSON.parse(readFileSync(0, 'utf8'))
} catch {
  fail('stdin is not JSON')
}
const { fixup, message, edits } = input
if ((fixup === undefined) === (message === undefined)) fail('give `fixup` or `message`, not both or neither')
if (!Array.isArray(edits) || edits.length === 0) fail('`edits` must be a non-empty array')
for (const edit of edits)
  if (typeof edit?.file !== 'string' || !Number.isInteger(edit.line) || typeof edit.before !== 'string' || typeof edit.after !== 'string')
    fail('each edit needs `file`, `line`, `before` and `after`')

const top = git(['rev-parse', '--show-toplevel']).trim()
process.chdir(top)
try {
  git(['diff', '--cached', '--quiet'])
} catch {
  fail('something is already staged; commit or unstage it first, so the commit holds only the review edits')
}
if (fixup !== undefined) {
  try {
    git(['rev-parse', '--verify', '--quiet', `${fixup}^{commit}`])
  } catch {
    fail(`${fixup} is not a commit`)
  }
}

// Every file's new working tree and index text, worked out before anything is written.
const files = new Map()
for (const edit of edits) {
  if (!files.has(edit.file)) {
    const staged = git(['ls-files', '--stage', '--', edit.file]).trim()
    if (staged === '') fail(`${edit.file} is not tracked; leave this change uncommitted`)
    const tree = readFileSync(join(top, edit.file), 'utf8')
    const index = git(['show', `:${edit.file}`])
    files.set(edit.file, { mode: staged.split(' ')[0], tree: tree.split('\n'), index: index.split('\n'), edits: [] })
  }
  files.get(edit.file).edits.push(edit)
}
for (const [file, copy] of files) {
  // Bottom up, so an edit never moves the lines of one still to come.
  const placed = copy.edits.map(edit => ({ edit, at: locate(edit, copy.tree, copy.index, file) }))
  placed.sort((a, b) => b.at.tree - a.at.tree)
  for (const { edit, at } of placed) {
    splice(copy.tree, at.tree, edit)
    splice(copy.index, at.index, edit)
  }
}

if (isCheck) {
  process.stdout.write(`${JSON.stringify({ ok: true, files: [...files.keys()] })}\n`)
  process.exit(0)
}

for (const [file, copy] of files) {
  const blob = git(['hash-object', '-w', '--no-filters', '--stdin'], copy.index.join('\n')).trim()
  git(['update-index', '--cacheinfo', `${copy.mode},${blob},${file}`])
  writeFileSync(join(top, file), copy.tree.join('\n'))
}

try {
  if (fixup !== undefined) git(['commit', '--quiet', `--fixup=${fixup}`])
  else git(['commit', '--quiet', '-F', '-'], message)
} catch (error) {
  // The edits stay in the working tree; only the index goes back, so nothing half-staged is left behind.
  git(['reset', '--quiet', '--', ...files.keys()])
  fail(`git commit failed, the edits are left uncommitted: ${String(error.stderr || error.message).trim()}`)
}

const [commit, subject] = git(['log', '-1', '--format=%h%x00%s']).trim().split('\0')
process.stdout.write(`${JSON.stringify({ ok: true, commit, subject })}\n`)
