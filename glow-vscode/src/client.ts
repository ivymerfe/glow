import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

const enum GlowCommandType {
  WINDOW_CREATE = 0,
  WINDOW_DESTROY = 1,
  WINDOW_VISIBLE = 2,
  WINDOW_FULLSCREEN = 3,
  WINDOW_SUSPEND = 4,
  WINDOW_PROGRAM = 5,
}

const enum GlowMessageType {
  WINDOW_CLOSED = 0,
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

export type GlowClientOptions = {
  executablePath: string;
  args?: string[];
  onInfo?: (message: string) => void;
  onWarning?: (message: string) => void;
  onError?: (message: string) => void;
  onStderr?: (chunk: string) => void;
  onExit?: (code: number | null, signal: NodeJS.Signals | null) => void;
  onWindowClosed?: (windowId: number, key: string | undefined) => void;
};

export type Window = {
  id: number;
  key: string;
  visible: boolean;
};

export class GlowClient {
  private proc: ChildProcessWithoutNullStreams | undefined;
  private readonly windows = new Map<string, Window>();
  private readonly windowIdToKey = new Map<number, string>();
  private nextWindowId = 1;
  private options: GlowClientOptions | undefined;
  private stdoutBuffer: Buffer = Buffer.alloc(0);

  setOptions(options: GlowClientOptions) {
    this.options = options;
  }

  start(): boolean {
    const exe = this.options.executablePath;
    const args = this.options.args ?? [];

    try {
      this.proc = spawn(exe, args, {
        stdio: ["pipe", "pipe", "pipe"],
      });
    } catch (e) {
      this.proc = undefined;
      this.options.onError?.(
        `Glow: failed to start '${exe}'. Check executablePath.`,
      );
      return false;
    }

    this.proc.on("error", () => {
      const opts = this.options;
      this.proc = undefined;
      opts?.onError?.(
        "Glow: subprocess failed. Check executablePath and PATH.",
      );
    });
    this.proc.on("exit", (code, signal) => {
      const opts = this.options;
      opts?.onExit?.(code, signal);
      this.proc = undefined;
      this.windows.clear();
      this.windowIdToKey.clear();
      this.stdoutBuffer = Buffer.alloc(0);
      if (code !== null) {
        opts?.onWarning?.(`Glow: subprocess exited with code ${code}.`);
        if (code === 0) {
          opts?.onWarning?.(`Glow: restarting in 1s`);
          setTimeout(() => this.start(), 1000);          
        }
        if (code === 127) {
          opts?.onError?.("Glow: check slang shared libraries");
        }
      } else if (signal) {
        opts?.onWarning?.(`Glow: subprocess exited with signal ${signal}.`);
      } else {
        opts?.onWarning?.("Glow: subprocess exited.");
      }
    });
    this.proc.stderr.on("data", (_chunk) => {
      const opts = this.options;
      const str = _chunk.toString();
      opts?.onStderr?.(str);
    });
    this.proc.stdout.on("data", (_chunk) => {
      this.handleStdoutChunk(_chunk);
    });

    return true;
  }

  isRunning(): boolean {
    return !!this.proc && !this.proc.killed;
  }

  private write(buf: Buffer) {
    if (!this.proc || this.proc.killed) return;
    this.proc.stdin.write(buf);
  }

  private handleStdoutChunk(chunk: Buffer) {
    if (chunk.byteLength === 0) return;
    this.stdoutBuffer = this.stdoutBuffer.byteLength
      ? Buffer.concat([this.stdoutBuffer, chunk])
      : chunk;

    while (this.stdoutBuffer.byteLength >= 4) {
      const payloadLen = this.stdoutBuffer.readUInt32LE(0);
      if (payloadLen > 16 * 1024 * 1024) {
        this.options?.onWarning?.(
          `Glow: dropping stdout buffer (invalid message length ${payloadLen}).`,
        );
        this.stdoutBuffer = Buffer.alloc(0);
        return;
      }

      const frameLen = 4 + payloadLen;
      if (this.stdoutBuffer.byteLength < frameLen) return;

      const payload = this.stdoutBuffer.subarray(4, frameLen);
      this.stdoutBuffer = this.stdoutBuffer.subarray(frameLen);
      this.handleMessage(payload);
    }
  }

  private handleMessage(payload: Buffer) {
    if (payload.byteLength < 1) return;
    const type = payload.readUInt8(0);
    switch (type) {
      case GlowMessageType.WINDOW_CLOSED: {
        if (payload.byteLength < 5) return;
        const windowId = payload.readUInt32LE(1);
        this.handleWindowClosed(windowId);
        break;
      }
      default:
        this.options?.onWarning?.(`Glow: unknown message type ${type}.`);
        break;
    }
  }

  private handleWindowClosed(windowId: number) {
    const key = this.windowIdToKey.get(windowId);
    if (key) {
      this.windowIdToKey.delete(windowId);
      this.windows.delete(key);
    }
    this.options?.onWindowClosed?.(windowId, key);
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

  private cmdWindowFullscreen(windowId: number) {
    this.write(frame(GlowCommandType.WINDOW_FULLSCREEN, u32le(windowId)));
  }

  private cmdWindowSuspend(windowId: number) {
    this.write(frame(GlowCommandType.WINDOW_SUSPEND, u32le(windowId)));
  }

  private cmdWindowProgram(windowId: number, filePath: string, source: string) {
    const pathBytes = Buffer.from(filePath, "utf8");
    const srcBytes = Buffer.from(source, "utf8");
    const payload = Buffer.concat([
      u32le(windowId),
      u32le(pathBytes.byteLength),
      u32le(srcBytes.byteLength),
      pathBytes,
      srcBytes,
    ]);
    this.write(frame(GlowCommandType.WINDOW_PROGRAM, payload));
  }

  getOrCreateWindow(key: string): Window {
    const win = this.windows.get(key);
    if (win) {
      this.cmdWindowVisible(win.id, true);
      return win;
    }
    const id = this.nextWindowId++;
    const new_window: Window = { id, key, visible: true };
    this.windows.set(key, new_window);
    this.windowIdToKey.set(id, key);
    this.cmdWindowCreate(id);
    return new_window;
  }

  isPreviewActive(key: string): boolean {
    return this.windows.has(key);
  }

  openPreview(key: string, filePath: string, source: string): Window {
    const win = this.getOrCreateWindow(key);
    this.cmdWindowProgram(win.id, filePath, source);
    return win;
  }

  closePreview(key: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.windows.delete(key);
    this.windowIdToKey.delete(win.id);
    this.cmdWindowDestroy(win.id);
  }

  togglePreview(
    key: string,
    filePath: string,
    source: string,
  ): "opened" | "closed" {
    const win = this.windows.get(key);
    if (!win) {
      this.openPreview(key, filePath, source);
      return "opened";
    }
    if (!win.visible) {
      this.cmdWindowVisible(win.id, true);
      win.visible = true;
      return "opened";
    }
    this.closePreview(key);
    return "closed";
  }

  updatePreview(key: string, filePath: string, source: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.cmdWindowProgram(win.id, filePath, source);
  }

  toggleWindowVisible(key: string) {
    const win = this.windows.get(key);
    if (!win) return;
    win.visible = !win.visible;
    this.cmdWindowVisible(win.id, win.visible);
  }

  toggleFullscreen(key: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.cmdWindowFullscreen(win.id);
  }

  suspendWindow(key: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.cmdWindowSuspend(win.id);
  }

  dispose() {
    this.windows.clear();
    this.windowIdToKey.clear();
    this.stdoutBuffer = Buffer.alloc(0);
    if (this.proc && !this.proc.killed) {
      this.proc.kill();
    }
    this.proc = undefined;
    this.options = undefined;
  }
}
