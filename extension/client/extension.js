// extension.js — VS Code client for the VuurRaaf language server.
//
// Spawns `vr lsp` (the toolchain's built-in language server) and wires up
// diagnostics, go-to-definition, and hover for .vr / .vrmm files.
// The toolchain binary defaults to `vr` on PATH; override it with the
// `vuurraaf.toolchainPath` setting.

const vscode = require('vscode');
const {
	LanguageClient,
	TransportKind,
} = require('vscode-languageclient/node');

let client;

function activate(context) {
	const config = () => vscode.workspace.getConfiguration('vuurraaf');
	const toolchain = () => config().get('toolchainPath', 'vr');

	const serverOptions = {
		command: toolchain(),
		args: ['lsp'],
		transport: TransportKind.stdio,
	};

	const clientOptions = {
		documentSelector: [{ scheme: 'file', language: 'vuurraaf' }],
		synchronize: {
			// re-publish diagnostics when a settings change or a file is saved
			fileEvents: vscode.workspace.createFileSystemWatcher('**/*.{vr,vrmm}'),
		},
	};

	client = new LanguageClient('vuurraaf', 'VuurRaaf', serverOptions, clientOptions);
	client.start();

	context.subscriptions.push(
		vscode.commands.registerCommand('vuurraaf.restartServer', async () => {
			await client.stop();
			client = new LanguageClient('vuurraaf', 'VuurRaaf', serverOptions, clientOptions);
			client.start();
			vscode.window.showInformationMessage('VuurRaaf language server restarted.');
		})
	);
}

function deactivate() {
	if (client) {
		return client.stop();
	}
}

module.exports = { activate, deactivate };
