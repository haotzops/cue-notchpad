// Cue Notchpad × Pi integration — managed by Cue. Do not edit by hand.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { randomBytes } from "node:crypto";
import { chmod, mkdtemp, rm } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROTOCOL_VERSION = 1;
const MAXIMUM_REQUEST_BYTES = 4 * 1024;
const MAXIMUM_MESSAGE_BYTES = 256 * 1024;
const SOCKET_ENVIRONMENT_KEY = "CUE_PI_BRIDGE_SOCKET";
const TOKEN_ENVIRONMENT_KEY = "CUE_PI_BRIDGE_TOKEN";

interface BridgeRuntime {
  directory: string;
  socketPath: string;
  token: string;
  server: Server;
}

function textFromAssistantMessage(message: unknown): string | undefined {
  if (!message || typeof message !== "object") return undefined;
  const candidate = message as { role?: unknown; content?: unknown };
  if (candidate.role !== "assistant" || !Array.isArray(candidate.content)) return undefined;
  const text = candidate.content
    .filter((block): block is { type: "text"; text: string } =>
      Boolean(block)
        && typeof block === "object"
        && (block as { type?: unknown }).type === "text"
        && typeof (block as { text?: unknown }).text === "string"
    )
    .map((block) => block.text)
    .join("\n")
    .trim();
  return text || undefined;
}

export function latestAssistantText(ctx: Pick<ExtensionContext, "sessionManager">): string | undefined {
  const branch = ctx.sessionManager.getBranch();
  for (let index = branch.length - 1; index >= 0; index -= 1) {
    const entry = branch[index] as {
      type?: unknown;
      message?: { role?: unknown };
    };
    if (entry.type !== "message" || entry.message?.role !== "assistant") continue;
    const text = textFromAssistantMessage(entry.message);
    return text ? truncateUTF8(text, MAXIMUM_MESSAGE_BYTES) : undefined;
  }
  return undefined;
}

function truncateUTF8(text: string, maximumBytes: number): string {
  const bytes = Buffer.from(text, "utf8");
  if (bytes.length <= maximumBytes) return text;
  const decoder = new TextDecoder("utf-8", { fatal: true });
  for (let end = maximumBytes; end > 0; end -= 1) {
    try {
      return decoder.decode(bytes.subarray(0, end));
    } catch {
      // Back up to the previous complete UTF-8 scalar.
    }
  }
  return "";
}

function handleClient(socket: Socket, token: string, ctx: ExtensionContext): void {
  let request = Buffer.alloc(0);
  socket.setTimeout(1_000, () => socket.destroy());
  socket.on("data", (chunk: Buffer) => {
    request = Buffer.concat([request, chunk]);
    if (request.length > MAXIMUM_REQUEST_BYTES) {
      socket.destroy();
      return;
    }
    const newline = request.indexOf(0x0a);
    if (newline < 0) return;
    if (newline !== request.length - 1) {
      socket.destroy();
      return;
    }

    try {
      const decoded = JSON.parse(request.subarray(0, newline).toString("utf8")) as {
        version?: unknown;
        token?: unknown;
      };
      if (decoded.version !== PROTOCOL_VERSION || decoded.token !== token) {
        socket.destroy();
        return;
      }
      const response = {
        version: PROTOCOL_VERSION,
        sessionID: ctx.sessionManager.getSessionId(),
        leafID: ctx.sessionManager.getLeafId() ?? null,
        message: latestAssistantText(ctx) ?? "",
      };
      socket.end(`${JSON.stringify(response)}\n`);
    } catch {
      socket.destroy();
    }
  });
  socket.on("error", () => socket.destroy());
}

async function closeRuntime(runtime: BridgeRuntime | undefined): Promise<void> {
  if (!runtime) return;
  if (process.env[SOCKET_ENVIRONMENT_KEY] === runtime.socketPath) {
    delete process.env[SOCKET_ENVIRONMENT_KEY];
  }
  if (process.env[TOKEN_ENVIRONMENT_KEY] === runtime.token) {
    delete process.env[TOKEN_ENVIRONMENT_KEY];
  }
  await new Promise<void>((resolve) => runtime.server.close(() => resolve()));
  await rm(runtime.directory, { recursive: true, force: true });
}

export default function (pi: ExtensionAPI) {
  let runtime: BridgeRuntime | undefined;

  pi.on("session_start", async (_event, ctx) => {
    await closeRuntime(runtime);
    const directory = await mkdtemp(join(tmpdir(), "cue-pi-bridge-"));
    await chmod(directory, 0o700);
    const socketPath = join(directory, "context.sock");
    const token = randomBytes(32).toString("hex");
    const server = createServer((socket) => handleClient(socket, token, ctx));

    try {
      await new Promise<void>((resolve, reject) => {
        server.once("error", reject);
        server.listen(socketPath, () => {
          server.off("error", reject);
          resolve();
        });
      });
      await chmod(socketPath, 0o600);
      runtime = { directory, socketPath, token, server };
      process.env[SOCKET_ENVIRONMENT_KEY] = socketPath;
      process.env[TOKEN_ENVIRONMENT_KEY] = token;
    } catch (error) {
      server.close();
      await rm(directory, { recursive: true, force: true });
      throw error;
    }
  });

  pi.on("session_shutdown", async () => {
    const closing = runtime;
    runtime = undefined;
    await closeRuntime(closing);
  });
}
