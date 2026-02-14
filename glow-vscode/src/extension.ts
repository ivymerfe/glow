import * as vscode from "vscode";
import * as path from "node:path";
import { GlowClient } from "./client";

function isShaderDocument(doc: vscode.TextDocument): boolean {
  if (doc.uri.scheme !== "file") return false;
  if (doc.languageId === "slang") return true;
  const ext = path.extname(doc.uri.fsPath).toLowerCase();
  return ext === ".slang" || ext === ".slangh";
}

const glow = new GlowClient();

const pendingUpdateTimers = new Map<string, NodeJS.Timeout>();

function cancelPendingUpdate(key: string) {
  const t = pendingUpdateTimers.get(key);
  if (t) clearTimeout(t);
  pendingUpdateTimers.delete(key);
}

function scheduleUpdate(key: string, fn: () => void, debounceMs = 75) {
  cancelPendingUpdate(key);
  const t = setTimeout(() => {
    pendingUpdateTimers.delete(key);
    fn();
  }, debounceMs);
  pendingUpdateTimers.set(key, t);
}

function getActiveShaderDocument(options?: {
  requireRunning?: boolean;
  requirePreviewActive?: boolean;
}): vscode.TextDocument | undefined {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return undefined;

  const doc = editor.document;
  if (!isShaderDocument(doc)) {
    void vscode.window.showWarningMessage("Glow: not a .slang/.slangh file.");
    return undefined;
  }

  if (options?.requireRunning && !glow.isRunning()) {
    void vscode.window.showErrorMessage(
      "Glow: process isn't running. Check 'glow.executablePath'.",
    );
    return undefined;
  }

  if (
    options?.requirePreviewActive &&
    !glow.isPreviewActive(doc.uri.toString())
  ) {
    void vscode.window.showWarningMessage(
      "Glow: no active preview for this file.",
    );
    return undefined;
  }

  return doc;
}

export function activate(context: vscode.ExtensionContext) {
  const cfg = vscode.workspace.getConfiguration("glow");
  const exe = cfg.get<string>("executablePath", "glow");
  const args = cfg.get<string[]>("args", []);

  glow.start({
    executablePath: exe,
    args,
    onError: (message) => {
      void vscode.window.showErrorMessage(message);
    },
    onWarning: (message) => {
      void vscode.window.showWarningMessage(message);
    },
    onStderr: (chunk) => {
      console.log(`[Glow] ${chunk}`);
    },
    onWindowClosed: (_windowId, key) => {
      if (key) cancelPendingUpdate(key);
    },
  });

  context.subscriptions.push({
    dispose: () => {
      for (const t of pendingUpdateTimers.values()) clearTimeout(t);
      pendingUpdateTimers.clear();
      glow.dispose();
    },
  });

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.togglePreview", () => {
      const doc = getActiveShaderDocument({ requireRunning: true });
      if (!doc) return;
      const key = doc.uri.toString();
      const action = glow.togglePreview(key, doc.uri.fsPath, doc.getText());
      if (action === "closed") cancelPendingUpdate(key);
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.hideOrShowWindow", () => {
      const doc = getActiveShaderDocument({
        requireRunning: true,
        requirePreviewActive: true,
      });
      if (!doc) return;
      glow.toggleWindowVisible(doc.uri.toString());
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.suspendWindow", () => {
      const doc = getActiveShaderDocument({
        requireRunning: true,
        requirePreviewActive: true,
      });
      if (!doc) return;
      glow.suspendWindow(doc.uri.toString());
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.fullscreenWindow", () => {
      const doc = getActiveShaderDocument({
        requireRunning: true,
        requirePreviewActive: true,
      });
      if (!doc) return;
      glow.toggleFullscreen(doc.uri.toString());
    }),
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeTextDocument((e) => {
      if (!isShaderDocument(e.document)) return;
      const key = e.document.uri.toString();
      if (!glow.isPreviewActive(key)) return;
      scheduleUpdate(key, () => {
        glow.updatePreview(key, e.document.uri.fsPath, e.document.getText());
      });
    }),
  );

  context.subscriptions.push(
    vscode.workspace.onDidCloseTextDocument((doc) => {
      const key = doc.uri.toString();
      cancelPendingUpdate(key);
      glow.closePreview(key);
    }),
  );
}

export function deactivate() {
  for (const t of pendingUpdateTimers.values()) clearTimeout(t);
  pendingUpdateTimers.clear();
  glow.dispose();
}
