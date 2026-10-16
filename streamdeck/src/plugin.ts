// TokenBar for Stream Deck: AI usage limits on keys and dials. Data comes from the TokenBar app's
// local API (127.0.0.1 only) or its files in ~/.tokenbar; nothing is sent anywhere.
import streamDeck, { LogLevel } from "@elgato/streamdeck";

import { CountdownAction } from "./actions/countdown";
import { UsageAction } from "./actions/usage";

streamDeck.logger.setLevel(LogLevel.INFO);
streamDeck.actions.registerAction(new UsageAction());
streamDeck.actions.registerAction(new CountdownAction());
streamDeck.connect();
