// memd for OmO: the project memory brief joins the system prompt, and compaction
// or session end triggers memd's per-project sync, as its Claude Code hooks do.
import { execFile } from "node:child_process";

const MEMD = process.env.MEMD_BIN || "memd";

const hook = (event, cwd, signal) =>
	new Promise((resolve) => {
		const child = execFile(MEMD, ["hook", event], { timeout: 10000, signal }, (err, stdout) =>
			resolve(err ? "" : stdout),
		);
		child.stdin.on("error", () => {});
		child.stdin.end(JSON.stringify({ cwd }));
	});

export default function (pi) {
	let brief = Promise.resolve("");

	pi.on("session_start", (_event, ctx) => {
		brief = hook("session-start", ctx.cwd).then((out) => {
			try {
				return JSON.parse(out).hookSpecificOutput?.additionalContext ?? "";
			} catch {
				return "";
			}
		});
	});

	pi.on(
		"before_agent_start",
		async (event) => {
			const text = await brief;
			if (text) return { systemPrompt: `${event.systemPrompt}\n\n${text}` };
		},
		{ previewSafe: true },
	);

	pi.on("session_before_compact", (_event, ctx) => {
		hook("pre-compact", ctx.cwd);
	});
	pi.on("session_shutdown", async (event, ctx) => {
		if (event.reason !== "reload") await hook("session-end", ctx.cwd, event.signal);
	});
}
