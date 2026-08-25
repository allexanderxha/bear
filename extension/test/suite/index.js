// index.js — mocha bootstrap, executed inside the VS Code extension host.
const path = require('path');
const Mocha = require('mocha');

async function run() {
	const mocha = new Mocha({
		ui: 'tdd',
		timeout: 90000,
		reporter: 'spec',
	});
	mocha.addFile(path.join(__dirname, 'extension.test.js'));
	return new Promise((resolve, reject) => {
		mocha.run((failures) => {
			if (failures > 0) {
				reject(new Error(`${failures} test(s) failed`));
			} else {
				resolve();
			}
		});
	});
}

module.exports = { run };
