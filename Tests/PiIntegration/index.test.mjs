import assert from "node:assert/strict";
import { connect } from "node:net";
import { access, stat } from "node:fs/promises";
import extension, { latestAssistantText } from "../../Sources/CueCore/Resources/PiIntegration/pi-cue-context/index.ts";

const entries = [
  { type: "message", message: { role: "assistant", content: [{ type: "text", text: "older" }] } },
  { type: "message", message: { role: "toolResult", content: [{ type: "text", text: "secret tool output" }] } },
  {
    type: "message",
    message: {
      role: "assistant",
      content: [
        { type: "thinking", thinking: "private reasoning" },
        { type: "text", text: "latest agent turn" },
        { type: "toolCall", id: "1", name: "read", arguments: {} },
      ],
    },
  },
];
const sessionManager = {
  getBranch: () => entries,
  getSessionId: () => "session-1",
  getLeafId: () => "leaf-1",
};
assert.equal(latestAssistantText({ sessionManager }), "latest agent turn");
assert.equal(latestAssistantText({ sessionManager: { ...sessionManager, getBranch: () => [] } }), undefined);
assert.equal(latestAssistantText({
  sessionManager: {
    ...sessionManager,
    getBranch: () => [
      ...entries,
      { type: "message", message: { role: "assistant", content: [{ type: "toolCall", id: "2", name: "read", arguments: {} }] } },
    ],
  },
}), undefined);

const handlers = new Map();
extension({ on: (name, handler) => handlers.set(name, handler) });
await handlers.get("session_start")({}, { sessionManager });

const socketPath = process.env.CUE_PI_BRIDGE_SOCKET;
const token = process.env.CUE_PI_BRIDGE_TOKEN;
assert.ok(socketPath);
assert.match(token, /^[0-9a-f]{64}$/);
assert.equal((await stat(socketPath)).mode & 0o777, 0o600);

const rejected = await new Promise((resolve) => {
  const socket = connect(socketPath);
  let data = "";
  socket.on("connect", () => socket.write(`${JSON.stringify({ version: 1, token: "0".repeat(64) })}\n`));
  socket.on("data", (chunk) => { data += chunk.toString("utf8"); });
  socket.on("close", () => resolve(data));
});
assert.equal(rejected, "");

const response = await new Promise((resolve, reject) => {
  const socket = connect(socketPath);
  let data = "";
  socket.on("connect", () => socket.write(`${JSON.stringify({ version: 1, token })}\n`));
  socket.on("data", (chunk) => { data += chunk.toString("utf8"); });
  socket.on("end", () => resolve(JSON.parse(data)));
  socket.on("error", reject);
});
assert.deepEqual(response, {
  version: 1,
  sessionID: "session-1",
  leafID: "leaf-1",
  message: "latest agent turn",
});

await handlers.get("session_shutdown")({}, { sessionManager });
assert.equal(process.env.CUE_PI_BRIDGE_SOCKET, undefined);
assert.equal(process.env.CUE_PI_BRIDGE_TOKEN, undefined);
await assert.rejects(access(socketPath));
console.log("Pi integration tests passed");
