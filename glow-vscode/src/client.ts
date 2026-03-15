import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

const enum GlowCommandType {
  WINDOW_CREATE = 0,
  WINDOW_DESTROY = 1,
  WINDOW_VISIBLE = 2,
  WINDOW_FULLSCREEN = 3,
  WINDOW_PROGRAM = 4,
}

const enum GlowMessageType {
  WINDOW_CLOSED = 0,
  WINDOW_VISIBLE = 1,
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

export type Window = {
  id: number;
  key: string;
  visible: boolean;
};

export class GlowClient {
  private proc: ChildProcessWithoutNullStreams | undefined;
  private readonly windows = new Map<string, Window>();
  private readonly windowIdToKey = new Map<number, string>();
  private nextWindowId = 0;
  private stdoutBuffer: Buffer = Buffer.alloc(0);

  public onError?: (message: string) => void;
  public onWarning?: (message: string) => void;
  public onExit?: (code: number | null, signal: NodeJS.Signals | null) => void;
  public onWindowClosed?: (windowId: number, key: string | undefined) => void;

  start(executablePath: string): boolean {
    try {
      this.proc = spawn(executablePath, [], {
        stdio: ["pipe", "pipe", "pipe"],
      });
    } catch (e) {
      this.proc = undefined;
      this.onError?.(
        `Glow: failed to start '${executablePath}'. Check executablePath.`,
      );
      return false;
    }

    this.proc.on("error", () => {
      this.proc = undefined;
      this.onError?.("Glow: subprocess failed. Check executablePath and PATH.");
    });
    this.proc.on("exit", (code, signal) => {
      this.onExit?.(code, signal);
      if (code !== null) {
        this.onWarning?.(`Glow: subprocess exited with code ${code}.`);
        if (code === 127) {
          this.onError?.("Glow: check slang shared libraries");
        }
      } else if (signal) {
        this.onWarning?.(`Glow: subprocess exited with signal ${signal}.`);
      } else {
        this.onWarning?.("Glow: subprocess exited.");
      }
      this.destroy();
    });
    this.proc.stderr.on("data", (chunk) => {
      console.log(chunk.toString());
    });
    this.proc.stdout.on("data", (chunk) => {
      this.handleStdoutChunk(chunk);
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
        this.onWarning?.(
          `Glow: dropping stdout buffer (invalid message length ${payloadLen}). ${chunk.toString()}`,
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
        const key = this.windowIdToKey.get(windowId);
        if (key) {
          this.windowIdToKey.delete(windowId);
          this.windows.delete(key);
        }
        this.onWindowClosed?.(windowId, key);
        break;
      }
      case GlowMessageType.WINDOW_VISIBLE: {
        if (payload.byteLength < 6) return;
        const windowId = payload.readUInt32LE(1);
        const visible = !!payload.readUInt8(5);
        const key = this.windowIdToKey.get(windowId);
        if (key) {
          const win = this.windows.get(key);
          if (win) {
            win.visible = visible;
          }
        }
        break;
      }
      default:
        this.onWarning?.(`Glow: unknown message type ${type}.`);
        break;
    }
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

  openPreview(key: string): Window {
    const win = this.getOrCreateWindow(key);
    return win;
  }

  closePreview(key: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.windows.delete(key);
    this.windowIdToKey.delete(win.id);
    this.cmdWindowDestroy(win.id);
  }

  updatePreview(key: string, filePath: string, source: string) {
    const win = this.windows.get(key);
    if (!win) return;
    this.cmdWindowProgram(win.id, filePath, source);
  }

  isWindowVisible(key: string): boolean {
    const win = this.windows.get(key);
    return !!win && win.visible;
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

  destroy() {
    this.windows.clear();
    this.windowIdToKey.clear();
    this.stdoutBuffer = Buffer.alloc(0);
    if (this.proc && !this.proc.killed) {
      this.proc.kill();
    }
    this.proc = undefined;
  }
}
