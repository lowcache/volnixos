// rtk for OmO: bash commands go through rtk's own rewrite rules, the engine its
// Claude Code PreToolUse hook uses. OMO_RTK=0 turns it off.
import { execFileSync } from "node:child_process";

export default function (pi) {
	if (process.env.OMO_RTK === "0") return;

	pi.on("tool_call", (event, ctx) => {
		if (event.toolName !== "bash" || typeof event.input?.command !== "string") return;
		try {
			const out = execFileSync("rtk", ["hook", "claude"], {
				input: JSON.stringify({
					hook_event_name: "PreToolUse",
					tool_name: "Bash",
					tool_input: { command: event.input.command },
					cwd: ctx.cwd,
				}),
				encoding: "utf8",
				stdio: ["pipe", "pipe", "ignore"],
				timeout: 2000,
			});
			const command = JSON.parse(out).hookSpecificOutput?.updatedInput?.command;
			if (typeof command === "string" && command) event.input.command = command;
		} catch {
			// Fail-open: no rewrite (empty output) or an rtk failure runs the command as written.
		}
	});
}
