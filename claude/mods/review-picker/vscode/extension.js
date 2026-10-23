const vscode = require('vscode')

// Opens a review page in VS Code's Simple Browser. The mod asks for it with
// vscode://dusc.review-picker-browser/open?url=<page url>, because `code --openExternal` always opens the system
// browser. It runs beside the page server (`extensionKind: workspace`), so asExternalUri forwards the port.
exports.activate = context => {
  context.subscriptions.push(
    vscode.window.registerUriHandler({
      async handleUri(uri) {
        if (uri.path !== '/open') return
        const url = new URLSearchParams(uri.query).get('url')
        // Only a page served on this machine, so a link elsewhere cannot use this to open an arbitrary site.
        if (url === null || !/^http:\/\/(127\.0\.0\.1|localhost):\d+\//.test(url)) return

        const external = await vscode.env.asExternalUri(vscode.Uri.parse(url))
        await vscode.commands.executeCommand('simpleBrowser.show', external.toString(true))
      },
    }),
  )
}
