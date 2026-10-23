import { expect, mock, test } from 'claude-code/testing'

const TOOL = 'mcp__review-picker__propose_changes'

const PANE = {
  plugin: 'review-picker',
  component: 'Pane',
  requestId: 'review-picker',
  props: {
    title: 'Review',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const CHANGES = [
  {
    file: 'app/models/user.rb',
    line: 10,
    reason: 'Says what the method returns',
    before: '  # This method gets the thing',
    after: '  # Returns the most recent active membership',
    context_after: '  def membership',
  },
  {
    file: 'app/models/user.rb',
    line: 40,
    reason: 'Restates the code',
    before: '  # increment the counter',
    after: '',
  },
]

test('ticked changes go back to Claude as a prompt, on every surface', async ($, on) => {
  const prompts: string[] = []
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })

  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const called = await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })
    expect(String(called.result)).toContain('numbered 1-2')

    const ui = await $.ui.mount({ ...PANE, surface })
    const removed = await ui.find({ type: 'Text', text: '-   # This method gets the thing' })
    expect(removed?.props.backgroundColor).toBe('diffRemoved')
    const added = await ui.find({ type: 'Text', text: '+   # Returns the most recent active membership' })
    expect(added?.props.backgroundColor).toBe('diffAdded')

    await ui.press({ key: 'toggle-2' })
    expect(await ui.find({ type: 'Button', text: /☐ 2\./ })).toBeDefined()
    await ui.press({ key: 'apply' })
    expect(prompts.at(-1)).toBe('Apply these changes from the "Comment accuracy" review: 1.\nSkip: 2.')
    expect(await ui.find({ key: 'apply' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a proposal is drawn as a description beside the edits', async ($, on) => {
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  await $.tool.call({
    tool: TOOL,
    title: 'Class composition',
    changes: [
      CHANGES[0],
      {
        reason: 'The controller builds and sends the export itself',
        proposal: 'Extract the CSV building into Exports::ParticipantCsv and call it from the controller.',
        files: ['app/controllers/exports_controller.rb', 'app/services/exports/participant_csv.rb'],
      },
    ],
  })

  for (const surface of ['terminal', 'desktop', 'vscode'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect(await ui.find({ type: 'Button', text: /☑ 2\. Proposal: app\/controllers\/exports_controller\.rb \+1 more/ }))
      .toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Extract the CSV building/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a malformed list is refused with the reason', async ($, on) => {
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'review-picker' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const called = await $.tool.call({
    tool: TOOL,
    title: 'Comment accuracy',
    changes: [{ file: 'a.rb', line: 0, reason: '', before: 'x', after: 'y' }],
  })
  expect(called.deny).toBe('changes[0].line must be a positive integer.')
})

const URL = 'http://127.0.0.1:40000/abc/'
const BROWSER = '/vscode/bin/helpers/browser.sh'
const CLI = '/vscode/bin/remote-cli/code'

test('the page sends the same reply as the pane, and opens through $BROWSER', async ($, on) => {
  const prompts: string[] = []
  const opened: string[][] = []
  const served: string[] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('prompt.submit', (_, e) => {
    prompts.push(e.text)

    return { text: e.text }
  })
  on('process.run', (_, e) => {
    opened.push([...e.argv])
    const stdout = e.argv[1] === '--list-extensions' ? 'anthropic.claude-code\n' : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  // Stands for server/review-server.mjs: prints its URL, then the numbers ticked on the page.
  on('process.spawn', async function* (_, e) {
    served.push(e.input ?? '')
    yield { stream: 'stdout' as const, text: `{"url":"${URL}"}\n{"sel` }
    yield { stream: 'stdout' as const, text: 'ected":[2]}\n' }

    return { value: { code: 0, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.press({ key: 'web' })

  expect(JSON.parse(served[0] ?? '{}').title).toBe('Comment accuracy')
  expect(opened).toEqual([
    [CLI, '--list-extensions'],
    [BROWSER, URL],
  ])
  expect(prompts).toEqual(['Apply these changes from the "Comment accuracy" review: 2.\nSkip: 1.'])
  expect(await ui.find({ type: 'Text', text: /Sent: apply 2; skip 1\./ })).toBeDefined()
  await ui.unmount()
})

test('with the VS Code extension installed, the page opens through it', async ($, on) => {
  const opened: string[][] = []
  mock.env(on, { BROWSER })
  on('tool.register', () => ({ value: { tool: TOOL } }))
  on('command.register', () => ({ value: { command: 'review-picker' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    opened.push([...e.argv])
    const stdout = e.argv[1] === '--list-extensions' ? 'anthropic.claude-code\ndusc.review-picker-browser\n' : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('process.spawn', async function* () {
    yield { stream: 'stdout' as const, text: `{"url":"${URL}"}\n` }

    return { value: { code: 0, signal: null } }
  })

  await $.session.start({ cwd: '/', surface: 'vscode', isInteractive: true })
  await $.tool.call({ tool: TOOL, title: 'Comment accuracy', changes: CHANGES })

  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  await ui.press({ key: 'web' })

  expect(opened.at(-1)).toEqual([
    BROWSER,
    'vscode://dusc.review-picker-browser/open?url=http%3A%2F%2F127.0.0.1%3A40000%2Fabc%2F',
  ])
  await ui.unmount()
})
