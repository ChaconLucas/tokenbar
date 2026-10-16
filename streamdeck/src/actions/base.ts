import streamDeck, {
	SingletonAction,
	type DidReceiveSettingsEvent,
	type JsonValue,
	type KeyAction,
	type DialAction,
	type KeyDownEvent,
	type SendToPluginEvent,
	type WillAppearEvent,
	type WillDisappearEvent,
} from "@elgato/streamdeck";

import { svgDataUrl, type KeyModel, type Scene } from "../render";
import { modelFor, providerItems, store, windowOf, type Settings } from "../store";

/**
 * Shared behavior of the TokenBar keys: settings cache per key, redraw on new data and on the
 * minute tick, key press toggles 5h/7d, and the AI dropdown of the property inspector.
 */
export abstract class TokenBarAction extends SingletonAction<Settings> {
	private settings = new Map<string, Settings>();
	private lastImage = new Map<string, string>();

	constructor() {
		super();
		store.subscribe(() => this.renderAll());
	}

	protected abstract scene(model: KeyModel): Scene;

	/** Encoder (Stream Deck +) feedback; only the usage action has one. */
	protected async renderDial(_action: DialAction<Settings>, _settings: Settings): Promise<void> {}

	override async onWillAppear(ev: WillAppearEvent<Settings>): Promise<void> {
		this.settings.set(ev.action.id, ev.payload.settings);
		this.lastImage.delete(ev.action.id);
		await this.render(ev.action, ev.payload.settings);
		void store.refresh();
	}

	override onWillDisappear(ev: WillDisappearEvent<Settings>): void {
		this.settings.delete(ev.action.id);
		this.lastImage.delete(ev.action.id);
	}

	override async onDidReceiveSettings(ev: DidReceiveSettingsEvent<Settings>): Promise<void> {
		this.settings.set(ev.action.id, ev.payload.settings);
		await this.render(ev.action, ev.payload.settings);
	}

	override async onKeyDown(ev: KeyDownEvent<Settings>): Promise<void> {
		await this.toggleWindow(ev.action, ev.payload.settings);
	}

	/** sdpi-components datasource: `<sdpi-select datasource="getProviders">`. */
	override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, Settings>): Promise<void> {
		const payload = ev.payload as { event?: string } | null;
		if (payload?.event !== "getProviders") return;
		await store.refresh();
		await streamDeck.ui.current?.sendToPropertyInspector({ event: "getProviders", items: providerItems() });
	}

	protected async toggleWindow(action: KeyAction<Settings> | DialAction<Settings>, current: Settings): Promise<void> {
		const settings: Settings = { ...current, window: windowOf(current) === "5h" ? "7d" : "5h" };
		await this.save(action, settings);
	}

	protected async save(action: KeyAction<Settings> | DialAction<Settings>, settings: Settings): Promise<void> {
		this.settings.set(action.id, settings);
		await action.setSettings(settings);
		await this.render(action, settings);
	}

	protected async render(action: KeyAction<Settings> | DialAction<Settings>, settings: Settings): Promise<void> {
		try {
			if (action.isDial()) return await this.renderDial(action, settings);
			if (!action.isKey()) return;
			const image = svgDataUrl(this.scene(modelFor(settings)));
			if (this.lastImage.get(action.id) === image) return;
			this.lastImage.set(action.id, image);
			await action.setImage(image);
		} catch (e) {
			streamDeck.logger.warn(`render failed: ${String(e)}`);
		}
	}

	private renderAll(): void {
		for (const action of this.actions) void this.render(action, this.settings.get(action.id) ?? {});
	}
}
