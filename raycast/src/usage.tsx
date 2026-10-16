import { Action, ActionPanel, Color, getPreferenceValues, Icon, List, Keyboard } from "@raycast/api";
import { useCachedPromise, useCachedState } from "@raycast/utils";
import { OpenDocsAction, OpenTokenBarAction } from "./actions";
import {
  dotBar,
  duration,
  filterProviders,
  fmtPct,
  loadUsage,
  nowSec,
  Provider,
  resetText,
  SOURCE_LABEL,
  summaryLine,
  Usage,
  windowsLine,
} from "./data";

interface Prefs {
  providers?: string;
}

const severity = (pct: number) => (pct >= 95 ? Color.Red : pct >= 80 ? Color.Orange : undefined);
const when = (epoch: number | null) => (epoch ? new Date(epoch * 1000).toLocaleString() : "unknown");

function Detail({ p, usage }: { p: Provider; usage: Usage }) {
  return (
    <List.Item.Detail
      metadata={
        <List.Item.Detail.Metadata>
          <List.Item.Detail.Metadata.TagList title="AI">
            <List.Item.Detail.Metadata.TagList.Item text={p.name} color={p.color} />
          </List.Item.Detail.Metadata.TagList>
          {p.windows.map((w) => (
            <List.Item.Detail.Metadata.Label
              key={`${w.id}-pct`}
              title={`${w.label || w.id} window`}
              text={`${dotBar(w.usedNow)}  ${fmtPct(w.usedNow)}`}
            />
          ))}
          <List.Item.Detail.Metadata.Separator />
          {p.windows.map((w) => (
            <List.Item.Detail.Metadata.Label
              key={`${w.id}-reset`}
              title={`${w.label || w.id} resets`}
              text={w.resetsAt ? `${when(w.resetsAt)} (${resetText(w)})` : "unknown"}
            />
          ))}
          <List.Item.Detail.Metadata.Separator />
          <List.Item.Detail.Metadata.Label
            title="Last read"
            text={p.observedAt ? `${when(p.observedAt)} (${duration(nowSec() - p.observedAt)} ago)` : "unknown"}
          />
          <List.Item.Detail.Metadata.Label title="Source" text={SOURCE_LABEL[usage.source]} />
        </List.Item.Detail.Metadata>
      }
    />
  );
}

export default function Command() {
  const prefs = getPreferenceValues<Prefs>();
  const [showDetail, setShowDetail] = useCachedState("show-detail", false);
  const { data, isLoading, revalidate } = useCachedPromise(loadUsage, [], { keepPreviousData: true });
  const providers = filterProviders(data?.providers ?? [], prefs.providers);
  const allJson = data ? JSON.stringify({ updatedAt: data.updatedAt, providers }, null, 2) : "";
  const allSummary = providers.map(summaryLine).join("\n");

  const common = (
    <>
      <Action
        title={showDetail ? "Hide Details" : "Show Details"}
        icon={Icon.Sidebar}
        shortcut={{ modifiers: ["cmd"], key: "d" }}
        onAction={() => setShowDetail(!showDetail)}
      />
      <Action
        title="Refresh"
        icon={Icon.ArrowClockwise}
        shortcut={Keyboard.Shortcut.Common.Refresh}
        onAction={revalidate}
      />
      <OpenTokenBarAction />
      <OpenDocsAction />
    </>
  );

  return (
    <List isLoading={isLoading} isShowingDetail={showDetail && providers.length > 0} searchBarPlaceholder="Filter AIs">
      <List.EmptyView
        icon={Icon.Gauge}
        title={data?.providers.length ? "No AI matches the AIs preference" : "No usage found"}
        description={
          data?.providers.length
            ? "Clear or change the AIs preference to see them."
            : "Open the TokenBar app (it serves the local API and writes ~/.tokenbar/snapshot.json)."
        }
        actions={<ActionPanel>{common}</ActionPanel>}
      />
      {data &&
        providers.map((p) => {
          const first = p.windows[0];
          const reset = first ? resetText(first) : undefined;
          return (
            <List.Item
              key={p.id}
              icon={{ source: Icon.CircleFilled, tintColor: p.color }}
              title={p.name}
              subtitle={windowsLine(p)}
              keywords={[p.id]}
              accessories={[
                ...p.windows.map((w) => ({
                  tag: { value: `${w.label || w.id} ${fmtPct(w.usedNow)}`, color: severity(w.usedNow) ?? p.color },
                })),
                ...(reset ? [{ text: reset, icon: Icon.Clock }] : []),
              ]}
              detail={<Detail p={p} usage={data} />}
              actions={
                <ActionPanel>
                  <Action.CopyToClipboard title="Copy Summary" content={summaryLine(p)} />
                  <Action.CopyToClipboard
                    title="Copy as JSON"
                    content={JSON.stringify(p, null, 2)}
                    shortcut={Keyboard.Shortcut.Common.Copy}
                  />
                  <Action.CopyToClipboard title="Copy All as Summary" content={allSummary} />
                  <Action.CopyToClipboard title="Copy All as JSON" content={allJson} />
                  {common}
                </ActionPanel>
              }
            />
          );
        })}
    </List>
  );
}
