import { action } from "@elgato/streamdeck";

import { countdownKey, type KeyModel } from "../render";
import { TokenBarAction } from "./base";

/** "Reset countdown": time until one AI's window resets, inside a ring that drains with it. */
@action({ UUID: "com.chaconlucas.tokenbar.countdown" })
export class CountdownAction extends TokenBarAction {
	protected scene(model: KeyModel) {
		return countdownKey(model);
	}
}
