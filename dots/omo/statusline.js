// OmO footer line drawn by the Claude Code statusline (~/.claude/statusline.sh,
// starship profile "claude-code"): same bands, plus the 5h / 7d plan windows.
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const SCRIPT = process.env.OMO_STATUSLINE || join(homedir(), ".claude", "statusline.sh");
const WINDOWS = { "5h": "five_hour", "7d": "seven_day" };

export default function (pi) {
	const plan = {};
	let running = false;

	const render = (ctx) => {
		if (!ctx.hasUI || running) return;
		running = true;
		const usage = ctx.getContextUsage?.();
		const json = JSON.stringify({
			model: { id: ctx.model?.id ?? "?", display_name: ctx.model?.name ?? ctx.model?.id ?? "?" },
			workspace: { current_dir: ctx.cwd },
			cwd: ctx.cwd,
			context_window: {
				used_percentage: usage?.percent ?? 0,
				total_input_tokens: usage?.tokens ?? 0,
				total_output_tokens: 0,
				context_window_size: usage?.contextWindow ?? 0,
			},
			rate_limits: plan,
		});
		let out = "";
		try {
			const child = spawn("bash", [SCRIPT], { stdio: ["pipe", "pipe", "ignore"], timeout: 3000 });
			child.stdout.on("data", (d) => (out += d));
			child.on("error", () => (running = false));
			child.on("close", () => {
				running = false;
				const lines = out.split("\n").filter((l) => l.trim() !== "");
				if (lines.length > 0) ctx.ui.setWidget("statusline", lines, { placement: "belowEditor" });
			});
			child.stdin.end(json);
		} catch {
			running = false;
		}
	};

	// Anthropic reports plan usage on every subscription response as
	// anthropic-ratelimit-unified-{5h,7d}-utilization, a 0..1 fraction.
	pi.on("after_provider_response", (event, ctx) => {
		for (const [name, value] of Object.entries(event.headers ?? {})) {
			const m = /unified-(5h|7d)-utilization$/i.exec(name);
			const n = Number(value);
			if (!m || !Number.isFinite(n)) continue;
			plan[WINDOWS[m[1]]] = { used_percentage: n <= 1.5 ? n * 100 : n };
		}
		render(ctx);
	});
	pi.on("session_start", (_event, ctx) => render(ctx));
	pi.on("model_select", (_event, ctx) => render(ctx));
	pi.on("agent_end", (_event, ctx) => render(ctx));
}
