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

glow.onError = (message) => {
  void vscode.window.showErrorMessage(message);
};

glow.onWarning = (message) => {
  void vscode.window.showWarningMessage(message);
};

glow.onWindowClosed = (_windowId, key) => {
  if (key) cancelPendingUpdate(key);
};

function startGlowIfNeeded() {
  if (glow.isRunning()) return;

  const cfg = vscode.workspace.getConfiguration("glow");
  const exe = cfg.get<string>("executablePath", "glow");
  const args = cfg.get<string>("args", "").split(/\s+/);
  glow.start(exe, args);
}

export function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push({
    dispose: () => {
      for (const t of pendingUpdateTimers.values()) clearTimeout(t);
      pendingUpdateTimers.clear();
      glow.destroy();
    },
  });

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.preview", () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        return;
      }
      const doc = editor.document;
      if (!isShaderDocument(doc)) {
        void vscode.window.showWarningMessage(
          "Glow: not a .slang/.slangh file.",
        );
        return;
      }
      startGlowIfNeeded();
      const key = doc.uri.toString();
      if (glow.isPreviewActive(key)) {
        if (glow.isWindowVisible(key)) {
          glow.toggleFullscreen(key);
        } else {
          glow.toggleWindowVisible(key);
        }
      } else {
        glow.openPreview(key);
        glow.updatePreview(key, doc.uri.fsPath, doc.getText());
      }
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.stopPreview", () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        return;
      }
      const doc = editor.document;
      glow.closePreview(doc.uri.toString());
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.restart", () => {
      if (glow.isRunning()) {
        glow.destroy();
        void vscode.window.showInformationMessage("Glow: restarting...");
      }
      startGlowIfNeeded();
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.compileModule", () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        return;
      }
      const doc = editor.document;
      if (!isShaderDocument(doc)) {
        void vscode.window.showWarningMessage(
          "Glow: not a .slang/.slangh file.",
        );
        return;
      }
      startGlowIfNeeded();
      glow.compileModule(doc.uri.fsPath, doc.getText());
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("glow.compileToGlsl", () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        return;
      }
      const doc = editor.document;
      if (!isShaderDocument(doc)) {
        void vscode.window.showWarningMessage(
          "Glow: not a .slang/.slangh file.",
        );
        return;
      }
      startGlowIfNeeded();
      glow.compileToGlsl(doc.uri.fsPath, doc.getText());
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
  glow.destroy();
}
