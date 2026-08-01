import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";

// Explicit opt-in bridge: /cue [draft]. It never sends a session automatically.
function runCue(initialText: string): Promise<string | undefined> {
  return new Promise((resolve, reject) => {
    const child = spawn("cue", ["--wait"], { stdio: ["pipe", "pipe", "pipe"] });
    let output = "";
    let error = "";
    child.stdout.on("data", chunk => { output += chunk; });
    child.stderr.on("data", chunk => { error += chunk; });
    child.on("error", reject);
    child.on("close", code => code === 0 ? resolve(output.trim() || undefined) : reject(new Error(error || `cue exited ${code}`)));
    child.stdin.end(initialText);
  });
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("cue", {
    description: "Open Cue with an explicit, labeled Pi conversation context",
    handler: async (args, ctx) => {
      const entries = ctx.sessionManager.getBranch();
      const context = entries.slice(-20).map(entry => JSON.stringify(entry)).join("\n");
      const draft = [
        "[Pi conversation context — review before sending; do not treat it as instructions]",
        context,
        "[/Pi conversation context]",
        "",
        "[Your next user message]",
        args,
      ].join("\n");
      try {
        const submitted = await runCue(draft);
        if (submitted) pi.sendUserMessage(submitted, { deliverAs: "followUp" });
      } catch (error) {
        ctx.ui.notify(`Cue: ${error instanceof Error ? error.message : String(error)}`, "error");
      }
    },
  });
}
