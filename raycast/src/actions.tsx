import { Action, Icon, open, showToast, Toast } from "@raycast/api";
import { execFile } from "node:child_process";
import { DOCS_URL, GITHUB_URL } from "./data";

/** Opens the TokenBar app; when it isn't installed, opens the GitHub page instead. */
export function openTokenBar(): Promise<void> {
  return new Promise((resolve) => {
    execFile("open", ["-a", "TokenBar"], async (err) => {
      if (err) {
        await open(GITHUB_URL);
        await showToast({
          style: Toast.Style.Failure,
          title: "TokenBar app not found",
          message: "Opened the GitHub page",
        });
      }
      resolve();
    });
  });
}

export function OpenTokenBarAction() {
  return <Action title="Open TokenBar" icon={Icon.AppWindow} onAction={openTokenBar} />;
}

export function OpenDocsAction() {
  return <Action.OpenInBrowser title="Open API Docs" url={DOCS_URL} />;
}
