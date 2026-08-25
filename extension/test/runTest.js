// runTest.js — launches a real VS Code instance with this extension loaded
// and runs the suite in test/suite. The workspace fixture's settings point
// the language client at the vr toolchain (VR_TOOLCHAIN env or `vr` on PATH).
//
//   npm test
//   VR_TOOLCHAIN=/path/to/vr npm test
const path = require('path');
const fs = require('fs');
const { runTests } = require('@vscode/test-electron');

async function main() {
	const workspace = path.join(__dirname, 'fixtures', 'workspace');
	const settingsDir = path.join(workspace, '.vscode');
	fs.mkdirSync(settingsDir, { recursive: true });
	const vr = process.env.VR_TOOLCHAIN || 'vr';
	fs.writeFileSync(
		path.join(settingsDir, 'settings.json'),
		JSON.stringify({ 'vuurraaf.toolchainPath': vr }, null, 2)
	);

	// default to the locally installed stable VS Code; override with
	// VSCODE_EXECUTABLE for CI runners that pre-install it
	const executable =
		process.env.VSCODE_EXECUTABLE ||
		'/Applications/Visual Studio Code.app/Contents/MacOS/Code';

	try {
		await runTests({
			vscodeExecutablePath: executable,
			extensionDevelopmentPath: path.resolve(__dirname, '..'),
			extensionTestsPath: path.join(__dirname, 'suite', 'index.js'),
			launchArgs: [workspace],
		});
		console.log('VuurRaaf extension tests passed.');
	} catch (err) {
		console.error('VuurRaaf extension tests failed:', err);
		process.exit(1);
	}
}

main();
