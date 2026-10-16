import {
  Color,
  getPreferenceValues,
  Icon,
  launchCommand,
  LaunchType,
  MenuBarExtra,
  open,
  Keyboard,
} from "@raycast/api";
import { getProgressIcon, useCachedPromise } from "@raycast/utils";
import { openTokenBar } from "./actions";
import {
  abbrOf,
  DOCS_URL,
  filterProviders,
  findWindow,
  fmtPct,
  loadUsage,
  peakOf,
  Provider,
  resetText,
  SOURCE_LABEL,
  UsageWindow,
} from "./data";

interface Prefs {
  window?: "5h" | "7d" | "both";
  providers?: string;
}

const severity = (pct: number) => (pct >= 95 ? Color.Red : pct >= 80 ? Color.Orange : Color.Green);

/** "CL 28%" or, with "both", "CL 28/39%". */
function titlePart(p: Provider, which: Prefs["window"]): string {
  const short = findWindow(p, "5h");
  const long = findWindow(p, "7d");
  const pct = (w: UsageWindow | undefined) => (w ? String(Math.round(w.usedNow)) : "–");
  if (which === "both") return `${abbrOf(p)} ${pct(short)}/${pct(long)}%`;
  const w = which === "7d" ? long : short;
  return `${abbrOf(p)} ${pct(w)}%`;
}

export default function Command() {
  const prefs = getPreferenceValues<Prefs>();
  const { data, isLoading, revalidate } = useCachedPromise(loadUsage, [], { keepPreviousData: true });
  const providers = filterProviders(data?.providers ?? [], prefs.providers);
  const peak = peakOf(providers);

  const title = providers.length ? providers.map((p) => titlePart(p, prefs.window ?? "5h")).join(" · ") : undefined;
  const icon = providers.length ? getProgressIcon(peak / 100, severity(peak)) : Icon.CircleProgress;

  return (
    <MenuBarExtra icon={icon} title={title} tooltip="TokenBar: AI usage" isLoading={isLoading}>
      {data && !providers.length && (
        <MenuBarExtra.Item
          title={data.providers.length ? "No AI matches the AIs preference" : "No usage found"}
          subtitle={data.providers.length ? undefined : "Is the TokenBar app running?"}
          icon={Icon.Warning}
        />
      )}
      {providers.map((p) => (
        <MenuBarExtra.Section key={p.id} title={p.name}>
          {p.windows.map((w) => (
            <MenuBarExtra.Item
              key={w.id}
              icon={{ source: Icon.CircleFilled, tintColor: p.color }}
              title={`${w.label || w.id}  ${fmtPct(w.usedNow)}`}
              subtitle={resetText(w)}
              onAction={() => launchCommand({ name: "usage", type: LaunchType.UserInitiated })}
            />
          ))}
        </MenuBarExtra.Section>
      ))}
      <MenuBarExtra.Section>
        {data && (
          <MenuBarExtra.Item
            title={`Source: ${SOURCE_LABEL[data.source]}`}
            subtitle={data.updatedAt ? new Date(data.updatedAt * 1000).toLocaleTimeString() : undefined}
          />
        )}
        <MenuBarExtra.Item
          title="Open TokenBar"
          icon={Icon.AppWindow}
          shortcut={Keyboard.Shortcut.Common.Open}
          onAction={openTokenBar}
        />
        <MenuBarExtra.Item title="API Docs" icon={Icon.Book} onAction={() => open(DOCS_URL)} />
        <MenuBarExtra.Item
          title="Refresh"
          icon={Icon.ArrowClockwise}
          shortcut={Keyboard.Shortcut.Common.Refresh}
          onAction={revalidate}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
