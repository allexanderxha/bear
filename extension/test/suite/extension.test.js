// extension.test.js — end-to-end tests for the VuurRaaf VS Code extension.
//
// These launch a real VS Code instance with the extension loaded, open a
// demo .vr file, and verify the full editing experience against the live
// `vr lsp` server: language registration, diagnostics, go-to-definition,
// and hover.

const assert = require('assert');
const path = require('path');
const vscode = require('vscode');

const DEMO_URI = vscode.Uri.file(
	path.join(__dirname, '..', 'fixtures', 'workspace', 'demo.vr')
);
const VASM_URI = vscode.Uri.file(
	path.join(__dirname, '..', 'fixtures', 'workspace', 'math.vasm')
);

async function openDemo() {
	const doc = await vscode.workspace.openTextDocument(DEMO_URI);
	await vscode.window.showTextDocument(doc);
	return doc;
}

async function waitForDiagnostics(timeoutMs) {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const diags = vscode.languages.getDiagnostics(DEMO_URI);
		if (diags.length > 0) {
			return diags;
		}
		await new Promise((r) => setTimeout(r, 500));
	}
	return vscode.languages.getDiagnostics(DEMO_URI);
}

suite('VuurRaaf extension', function () {
	this.timeout(90000);

	test('vuurraaf language (grammar) is registered', async function () {
		const langs = await vscode.languages.getLanguages();
		assert.ok(langs.includes('vuurraaf'), 'vuurraaf language id not registered');
		assert.ok(langs.includes('vuurraaf-asm'), 'vuurraaf-asm language id not registered');
	});

	test('.vasm files get the vuurraaf-asm language id', async function () {
		const doc = await vscode.workspace.openTextDocument(VASM_URI);
		await vscode.window.showTextDocument(doc);
		assert.strictEqual(doc.languageId, 'vuurraaf-asm', 'expected vuurraaf-asm, got ' + doc.languageId);
	});

	test('language server publishes compiler diagnostics', async function () {
		await openDemo();
		const diags = await waitForDiagnostics(30000);
		assert.ok(diags.length > 0, 'no diagnostics were published');
		const joined = diags.map((d) => d.message).join('; ');
		assert.ok(joined.includes('unknown_var'), 'expected unknown_var error, got: ' + joined);
		assert.strictEqual(diags[0].severity, vscode.DiagnosticSeverity.Error);
	});

	test('go-to-definition jumps to the function declaration', async function () {
		await openDemo();
		// "helper" in `let y = helper(21)` — line 6, char 12 (0-based)
		const pos = new vscode.Position(5, 12);
		const locs = await vscode.commands.executeCommand(
			'vscode.executeDefinitionProvider',
			DEMO_URI,
			pos
		);
		assert.ok(locs && locs.length > 0, 'no definition returned for helper');
		assert.strictEqual(locs[0].range.start.line, 0, 'helper should resolve to line 1');
	});

	test('hover reports the symbol kind', async function () {
		await openDemo();
		// on the local `y` — line 6, char 5
		const pos = new vscode.Position(5, 5);
		const hovers = await vscode.commands.executeCommand('vscode.executeHoverProvider', DEMO_URI, pos);
		assert.ok(hovers && hovers.length > 0, 'no hover returned for y');
		const text = hovers
			.map((h) => h.contents.map((c) => (typeof c === 'string' ? c : c.value)).join(' '))
			.join(' ');
		assert.ok(text.includes('variable'), 'expected a variable hover, got: ' + text);
	});

	test('go-to-definition resolves stdlib module functions', async function () {
		await openDemo();
		// switch to a file that calls os.exists so the import resolves
		const modUri = vscode.Uri.file(
			path.join(__dirname, '..', 'fixtures', 'workspace', 'module.vr')
		);
		const doc = await vscode.workspace.openTextDocument(modUri);
		await vscode.window.showTextDocument(doc);
		// "exists" in `let a = os.exists("x")` — line 4, char 12 (0-based)
		const pos = new vscode.Position(3, 12);
		// the definition request may race the didOpen notification, so retry
		let locs = [];
		for (let i = 0; i < 20 && locs.length === 0; i++) {
			locs = await vscode.commands.executeCommand(
				'vscode.executeDefinitionProvider',
				modUri,
				pos
			);
			if (locs.length === 0) {
				await new Promise((r) => setTimeout(r, 500));
			}
		}
		assert.ok(locs && locs.length > 0, 'no definition returned for os.exists');
		assert.ok(locs[0].uri.fsPath.endsWith('os.vr'), 'expected lib/os.vr, got ' + locs[0].uri.fsPath);
	});
});
