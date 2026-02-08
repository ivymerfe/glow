import * as vscode from 'vscode';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import * as path from 'node:path';

const enum GlowCommandType {
	WINDOW_CREATE = 0,
	WINDOW_DESTROY = 1,
	WINDOW_VISIBLE = 2,
	WINDOW_FULLSCREEN = 3,
	WINDOW_SUSPEND = 4,
	WINDOW_PROGRAM = 5,
}

function u32le(value: number): Buffer {
	const b = Buffer.allocUnsafe(4);
	b.writeUInt32LE(value >>> 0, 0);
	return b;
}

function u8(value: number): Buffer {
	const b = Buffer.allocUnsafe(1);
	b.writeUInt8(value & 0xff, 0);
	return b;
}

function frame(type: GlowCommandType, payload: Buffer): Buffer {
	const header = Buffer.allocUnsafe(5);
	header.writeUInt8(type, 0);
	header.writeUInt32LE(payload.byteLength >>> 0, 1);
	return Buffer.concat([header, payload]);
}

function isShaderDocument(doc: vscode.TextDocument): boolean {
	if (doc.uri.scheme !== 'file') return false;
	if (doc.languageId === 'slang') return true;
	const ext = path.extname(doc.uri.fsPath).toLowerCase();
	return ext === '.slang' || ext === '.slangh';
}

class GlowClient {
	private proc: ChildProcessWithoutNullStreams | undefined;
	private readonly windowIdByUri = new Map<string, number>();
	private nextWindowId = 1;
	private readonly pendingUpdateTimers = new Map<string, NodeJS.Timeout>();

	start(context: vscode.ExtensionContext) {
		const cfg = vscode.workspace.getConfiguration('glow');
		const exe = cfg.get<string>('executablePath', 'glow');
		const args = cfg.get<string[]>('args', []);

		try {
			this.proc = spawn(exe, args, {
				stdio: ['pipe', 'pipe', 'pipe'],
			});
		} catch (e) {
			this.proc = undefined;
			vscode.window.showErrorMessage(
				`Glow: failed to start '${exe}'. Configure 'glow.executablePath'.`,
			);
			return;
		}

		this.proc.on('error', () => {
			this.proc = undefined;
			vscode.window.showErrorMessage(
				"Glow: subprocess failed. Check 'glow.executablePath' and PATH.",
			);
		});
		this.proc.on('exit', (e) => {
			vscode.window.showWarningMessage(`Glow: subprocess exited with code ${e}.`);
			if (e == 127) {
				vscode.window.showErrorMessage(`Glow: check slang shared libraries`);
			}
			this.proc = undefined;
			this.windowIdByUri.clear();
			this.clearAllTimers();
		});

		// Don't spam output, but keep something visible for debugging.
		this.proc.stderr.on('data', (_chunk) => {
			console.error(`[Glow stderr] ${_chunk.toString()}`);
		});
		this.proc.stdout.on('data', (_chunk) => {
			console.log(`[Glow stdout] ${_chunk.toString()}`);
		});

		context.subscriptions.push({
			dispose: () => {
				this.dispose();
			},
		});
	}

	private clearAllTimers() {
		for (const t of this.pendingUpdateTimers.values()) clearTimeout(t);
		this.pendingUpdateTimers.clear();
	}

	private write(buf: Buffer) {
		if (!this.proc || this.proc.killed) return;
		this.proc.stdin.write(buf);
	}

	private cmdWindowCreate(windowId: number) {
		this.write(frame(GlowCommandType.WINDOW_CREATE, u32le(windowId)));
	}

	private cmdWindowDestroy(windowId: number) {
		this.write(frame(GlowCommandType.WINDOW_DESTROY, u32le(windowId)));
	}

	private cmdWindowVisible(windowId: number, visible: boolean) {
		this.write(
			frame(
				GlowCommandType.WINDOW_VISIBLE,
				Buffer.concat([u32le(windowId), u8(visible ? 1 : 0)]),
			),
		);
	}

	private cmdWindowProgram(windowId: number, filePath: string, source: string) {
		const pathBytes = Buffer.from(filePath, 'utf8');
		const srcBytes = Buffer.from(source, 'utf8');
		const payload = Buffer.concat([
			u32le(windowId),
			u32le(pathBytes.byteLength),
			u32le(srcBytes.byteLength),
			pathBytes,
			srcBytes,
		]);
		this.write(frame(GlowCommandType.WINDOW_PROGRAM, payload));
	}

	getOrCreateWindowId(uri: vscode.Uri): number {
		const key = uri.toString();
		const existing = this.windowIdByUri.get(key);
		if (existing) return existing;
		const id = this.nextWindowId++;
		this.windowIdByUri.set(key, id);
		this.cmdWindowCreate(id);
		return id;
	}

	isPreviewActive(uri: vscode.Uri): boolean {
		return this.windowIdByUri.has(uri.toString());
	}

	togglePreviewForDocument(doc: vscode.TextDocument) {
		if (!this.proc) {
			vscode.window.showErrorMessage(
				"Glow: process isn't running. Check 'glow.executablePath'.",
			);
			return;
		}
		if (!isShaderDocument(doc)) {
			void vscode.window.showWarningMessage('Glow: not a .slang/.slangh file.');
			return;
		}

		const key = doc.uri.toString();
		const existing = this.windowIdByUri.get(key);
		if (existing) {
			this.windowIdByUri.delete(key);
			this.cancelPendingUpdate(doc.uri);
			this.cmdWindowDestroy(existing);
			return;
		}

		const id = this.getOrCreateWindowId(doc.uri);
		this.cmdWindowProgram(id, doc.uri.fsPath, doc.getText());
	}

	updatePreview(doc: vscode.TextDocument) {
		if (!this.proc) return;
		const id = this.windowIdByUri.get(doc.uri.toString());
		if (!id) return;
		this.cmdWindowProgram(id, doc.uri.fsPath, doc.getText());
	}

	scheduleUpdate(doc: vscode.TextDocument, debounceMs = 75) {
		const key = doc.uri.toString();
		if (!this.windowIdByUri.has(key)) return;
		this.cancelPendingUpdate(doc.uri);
		const t = setTimeout(() => {
			this.pendingUpdateTimers.delete(key);
			this.updatePreview(doc);
		}, debounceMs);
		this.pendingUpdateTimers.set(key, t);
	}

	cancelPendingUpdate(uri: vscode.Uri) {
		const key = uri.toString();
		const existing = this.pendingUpdateTimers.get(key);
		if (existing) clearTimeout(existing);
		this.pendingUpdateTimers.delete(key);
	}

	closePreview(uri: vscode.Uri) {
		const key = uri.toString();
		const id = this.windowIdByUri.get(key);
		if (!id) return;
		this.windowIdByUri.delete(key);
		this.cancelPendingUpdate(uri);
		this.cmdWindowDestroy(id);
	}

	dispose() {
		this.clearAllTimers();
		// Best-effort: destroy any windows we created.
		for (const id of this.windowIdByUri.values()) {
			this.cmdWindowDestroy(id);
		}
		this.windowIdByUri.clear();
		if (this.proc && !this.proc.killed) {
			this.proc.kill();
		}
		this.proc = undefined;
	}
}

const glow = new GlowClient();

export function activate(context: vscode.ExtensionContext) {
	// Requirement: start glow subprocess on activation.
	glow.start(context);

	context.subscriptions.push(
		vscode.commands.registerCommand('glow.previewShader', () => {
			const editor = vscode.window.activeTextEditor;
			if (!editor) return;
			glow.togglePreviewForDocument(editor.document);
		}),
	);

	context.subscriptions.push(
		vscode.workspace.onDidChangeTextDocument((e) => {
			if (!isShaderDocument(e.document)) return;
			if (!glow.isPreviewActive(e.document.uri)) return;
			glow.scheduleUpdate(e.document);
		}),
	);

	context.subscriptions.push(
		vscode.workspace.onDidCloseTextDocument((doc) => {
			glow.closePreview(doc.uri);
		}),
	);
}

export function deactivate() {
	glow.dispose();
}
