import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import test from 'node:test';
import { buildContextInit, buildImportInit } from '../../../extensions/lib/nvim-scripts.ts';

const minimalInit = resolve('tests/minimal_init.lua');
const nvimBin = process.env.NVIM_BIN || 'nvim';

function git(repo: string, ...args: string[]) {
	return execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8' });
}

function runNvim(repo: string, stateDir: string, initPath: string) {
	const setup = `lua require('unified_review').setup({ local_git = { state_dir = ${JSON.stringify(stateDir)} } })`;
	return spawnSync(nvimBin, ['--headless', '-n', '-u', minimalInit, '--cmd', setup, '-S', initPath], {
		cwd: repo,
		encoding: 'utf8',
	});
}

test('generated pi bridge scripts export context and import feedback through real Neovim', () => {
	const workspace = mkdtempSync(join(tmpdir(), 'unified-review-bridge-'));
	const repo = join(workspace, 'repo');
	const stateDir = join(workspace, 'state');
	mkdirSync(repo, { recursive: true });
	try {
		git(repo, 'init', '--initial-branch', 'main');
		git(repo, 'config', 'user.email', 'bridge@example.invalid');
		git(repo, 'config', 'user.name', 'Bridge Test');
		writeFileSync(join(repo, 'example.lua'), 'return 1\n');
		git(repo, 'add', 'example.lua');
		git(repo, 'commit', '-m', 'base');
		writeFileSync(join(repo, 'example.lua'), 'return 2\n');
		git(repo, 'add', 'example.lua');
		git(repo, 'commit', '-m', 'change');

		const target = {
			kind: 'local_git',
			cwd: repo,
			base: 'HEAD~1',
			head: 'HEAD',
			range_kind: 'two_dot',
		};
		const contextPath = join(workspace, 'context.json');
		const contextDiagnosticsPath = join(workspace, 'context-diagnostics.json');
		const contextInitPath = join(workspace, 'context-init.lua');
		writeFileSync(contextInitPath, buildContextInit(contextPath, target, contextDiagnosticsPath));

		const contextResult = runNvim(repo, stateDir, contextInitPath);
		assert.equal(contextResult.status, 0, `${contextResult.stdout}\n${contextResult.stderr}`);
		const contextDiagnostics = JSON.parse(readFileSync(contextDiagnosticsPath, 'utf8'));
		assert.equal(contextDiagnostics.status, 'exported');
		const context = JSON.parse(readFileSync(contextPath, 'utf8'));
		assert.equal(context.schema, 'unified-review.agent-context.v1');
		assert.equal(context.files[0].path, 'example.lua');
		assert.match(context.files[0].raw_patch, /return 2/);

		const failedContextDiagnosticsPath = join(workspace, 'failed-context-diagnostics.json');
		const failedContextInitPath = join(workspace, 'failed-context-init.lua');
		writeFileSync(
			failedContextInitPath,
			buildContextInit(
				join(workspace, 'failed-context.json'),
				{ ...target, base: 'missing-ref' },
				failedContextDiagnosticsPath,
			),
		);
		const failedContextResult = runNvim(repo, stateDir, failedContextInitPath);
		assert.notEqual(failedContextResult.status, 0);
		const failedContextDiagnostics = JSON.parse(readFileSync(failedContextDiagnosticsPath, 'utf8'));
		assert.equal(failedContextDiagnostics.status, 'error');
		assert.match(failedContextDiagnostics.message, /Needed a single revision/);

		const feedbackPath = join(workspace, 'feedback.json');
		const diagnosticsPath = join(workspace, 'import-diagnostics.json');
		const importInitPath = join(workspace, 'import-init.lua');
		writeFileSync(
			feedbackPath,
			JSON.stringify({
				schema: 'unified-review.agent-feedback.v1',
				source: { name: 'bridge-test', run_id: 'run-1' },
				comments: [
					{
						id: 'file-1',
						body: 'Review this change.',
						target: { kind: 'file', path: 'example.lua' },
					},
				],
			}),
		);
		writeFileSync(importInitPath, buildImportInit(feedbackPath, diagnosticsPath, target));

		const importResult = runNvim(repo, stateDir, importInitPath);
		assert.equal(importResult.status, 0, `${importResult.stdout}\n${importResult.stderr}`);
		const diagnostics = JSON.parse(readFileSync(diagnosticsPath, 'utf8'));
		assert.equal(diagnostics.status, 'imported');
		assert.equal(diagnostics.result.imported_comments, 1);
		assert.equal(diagnostics.result.skipped.length, 0);
	} finally {
		rmSync(workspace, { recursive: true, force: true });
	}
});
