import { action, type DialAction, type DialDownEvent, type DialRotateEvent, type TouchTapEvent } from "@elgato/streamdeck";

import { usageKey, RED, WARN_AT, countdownText, type KeyModel } from "../render";
import { modelFor, store, type Settings } from "../store";
import { TokenBarAction } from "./base";

/** "AI usage": % used of one AI's 5h or 7d window. Key press or dial push toggles 5h/7d; rotating switches AI. */
@action({ UUID: "com.chaconlucas.tokenbar.usage" })
export class UsageAction extends TokenBarAction {
	protected scene(model: KeyModel) {
		return usageKey(model);
	}

	protected override async renderDial(action: DialAction<Settings>, settings: Settings): Promise<void> {
		const m = modelFor(settings);
		const pct = m.pct === null ? null : Math.max(0, Math.min(100, Math.round(m.pct)));
		const hot = pct !== null && pct >= WARN_AT;
		await action.setFeedback({
			title: `${m.provider?.name ?? m.abbr} · ${m.window}`,
			value: pct === null ? m.status ?? "OFF" : `${pct}%  ${countdownText(m.resetsInSeconds).toLowerCase()}`,
			indicator: { value: pct ?? 0, bar_fill_c: hot ? RED : m.color },
		});
	}

	override async onDialRotate(ev: DialRotateEvent<Settings>): Promise<void> {
		const ps = store.usage?.providers ?? [];
		if (!ps.length) return;
		const cur = Math.max(0, ps.findIndex((p) => p.id === (ev.payload.settings.provider ?? ps[0].id)));
		const next = ps[(((cur + Math.sign(ev.payload.ticks)) % ps.length) + ps.length) % ps.length];
		await this.save(ev.action, { ...ev.payload.settings, provider: next.id });
	}

	override async onDialDown(ev: DialDownEvent<Settings>): Promise<void> {
		await this.toggleWindow(ev.action, ev.payload.settings);
	}

	override async onTouchTap(ev: TouchTapEvent<Settings>): Promise<void> {
		await this.toggleWindow(ev.action, ev.payload.settings);
	}
}
