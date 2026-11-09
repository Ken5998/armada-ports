import {
  ButtonItem,
  ConfirmModal,
  Field,
  Navigation,
  PanelSection,
  PanelSectionRow,
  ProgressBarWithInfo,
  showModal,
  staticClasses,
} from "@decky/ui";
import {
  addEventListener,
  callable,
  definePlugin,
  FileSelectionType,
  openFilePicker,
  removeEventListener,
  toaster,
} from "@decky/api";
import { useEffect, useState } from "react";
import { FaGamepad } from "react-icons/fa";
import { t } from "./i18n";

type Release = { tag: string; version: string; page: string; commit?: string };
type Installed = {
  data: string;
  version: string;
  commit?: string;
  built: boolean;
  game_files: boolean;
  exe: string;
  start_dir: string;
};
type Job = {
  id: string;
  action: "install" | "update";
  state: "running" | "done" | "failed" | "cancelled";
  stage: string;
  percent: number | null;
  message: string;
  log: string;
  add_to_steam?: boolean;
  exe?: string;
  start_dir?: string;
  name?: string;
};
type Port = {
  id: string;
  name: string;
  game: string;
  page: string;
  supported: boolean;
  needs: string[];
  disc: string;
  build_minutes: [number, number | null] | null;
  space_gb: number | null;
  free_gb: number | null;
  installed: Installed | null;
  latest: Release | null;
  update: boolean;
  job: Job | null;
  launcher_dir: string | null;
  steam_appid: number | null;
  legacy_appid: number | null;
};
type State = { home: string; ports: Port[]; checked: number | null; plugin: { version: string } | null; current: string };
type Reply<T> = { ok: true; result: T } | { ok: false; error: string };
type PluginDownload = { path: string; version: string; sha256: string };

const getState = callable<[], Reply<State>>("get_state");
const checkUpdates = callable<[refresh: boolean], Reply<{ news: unknown[] }>>("check_updates");
const adopt = callable<[port: string, folder: string], Reply<Port>>("adopt");
const startJob = callable<[port: string, action: string, iso: string, bios: string, addToSteam: boolean], Reply<Job>>(
  "start_job",
);
const cancelJob = callable<[port: string], Reply<Job | null>>("cancel_job");
const uninstall = callable<[port: string], Reply<string[]>>("uninstall");
const setSteam = callable<[port: string, appid: number], Reply<null>>("set_steam");
const downloadPlugin = callable<[], Reply<PluginDownload>>("download_plugin");

const NAME = "Armada Ports";

type SteamApps = {
  AddShortcut(name: string, exe: string, startDir: string, launchOptions: string): Promise<number>;
  SetShortcutName(appid: number, name: string): void;
  SetShortcutExe(appid: number, exe: string): void;
  SetShortcutStartDir(appid: number, dir: string): void;
  RemoveShortcut(appid: number): void;
};
const steamApps = () => (window as unknown as { SteamClient: { Apps: SteamApps } }).SteamClient.Apps;
const appStore = () =>
  (window as unknown as { appStore?: { GetAppOverviewByAppID(id: number): unknown | null } }).appStore;

function inSteam(port: Port): boolean {
  return [port.steam_appid, port.legacy_appid].some((id) => !!id && !!appStore()?.GetAppOverviewByAppID(id));
}

// A non-Steam game, added through Steam itself: it shows up at once, no restart needed.
async function addToSteam(portId: string, name: string, exe: string, startDir: string): Promise<boolean> {
  try {
    const apps = steamApps();
    const appid = await apps.AddShortcut(name, exe, startDir, "");
    if (!appid) return false;
    apps.SetShortcutName(appid, name);
    apps.SetShortcutExe(appid, `"${exe}"`);
    apps.SetShortcutStartDir(appid, `"${startDir}"`);
    await setSteam(portId, appid);
    toaster.toast({ title: NAME, body: t.addedToSteam(name) });
    return true;
  } catch (e) {
    toaster.toast({ title: NAME, body: `${t.steamFailed} ${e}` });
    return false;
  }
}

// Decky's own installer: it asks for confirmation, replaces the plugin and reloads it.
const UPDATE = 2;
function deckyInstall(update: PluginDownload) {
  const backend = (window as unknown as { DeckyBackend: { call(route: string, ...args: unknown[]): Promise<unknown> } })
    .DeckyBackend;
  return backend.call("utilities/install_plugin", `file://${update.path}`, NAME, update.version, update.sha256, UPDATE);
}

// What the panel showed, kept outside the components so it comes back as it was when Steam
// rebuilds the panel (for example after a dialog).
const kept: { state?: State; open?: string } = {};

function statusLine(port: Port): string {
  if (port.job?.state === "running") return t.working(port.job.stage);
  if (!port.supported) return port.latest ? `${t.launcherOnly} · ${t.latest(port.latest.version)}` : t.launcherOnly;
  if (!port.installed) return t.notInstalled;
  if (!port.installed.built) return t.unfinished;
  if (port.update && port.latest) return t.updateTo(port.latest.version);
  return t.installedV(port.installed.version || "");
}

function versionLine(port: Port): string {
  const i = port.installed;
  if (!i) return "";
  const mine = [i.version && t.version(i.version), i.commit && t.commit(i.commit)].filter(Boolean).join(" · ");
  const latest = port.latest
    ? [port.latest.version, port.latest.commit && t.commit(port.latest.commit)].filter(Boolean).join(" · ")
    : "";
  return latest ? `${mine} — ${t.newest(latest)}` : mine;
}

async function pick(type: FileSelectionType, start: string, extensions?: string[]): Promise<string | null> {
  try {
    const res = await openFilePicker(type, start, type === FileSelectionType.FILE, true, undefined, extensions);
    return res.realpath || res.path;
  } catch {
    return null; // closed without a choice
  }
}

function confirm(title: string, body: string, ok: string, danger = false): Promise<boolean> {
  return new Promise((resolve) => {
    showModal(
      <ConfirmModal
        strTitle={title}
        strDescription={body}
        strOKButtonText={ok}
        strCancelButtonText={t.cancel}
        bDestructiveWarning={danger}
        onOK={() => resolve(true)}
        onCancel={() => resolve(false)}
      />,
    );
  });
}

function PortDetail({ port, home, reload }: { port: Port; home: string; reload: () => Promise<void> }) {
  const job = port.job;
  const running = job?.state === "running";

  const report = <T,>(reply: Reply<T>): T | undefined => {
    if (!reply.ok) {
      toaster.toast({ title: port.name, body: reply.error });
      return undefined;
    }
    return reply.result;
  };

  const build = async (action: "install" | "update", needIso: boolean) => {
    let iso = "";
    let bios = "";
    if (needIso) {
      iso = (await pick(FileSelectionType.FILE, home, ["iso", "ISO"])) ?? "";
      if (!iso) return;
      if (port.needs.includes("bios")) {
        bios = (await pick(FileSelectionType.FILE, home)) ?? "";
        if (!bios) return;
      }
    }
    const time = port.build_minutes ? t.buildTime(port.build_minutes[0], port.build_minutes[1]) : t.buildLong;
    const space = port.space_gb && action === "install" ? ` ${t.space(port.space_gb, port.free_gb)}` : "";
    if (!(await confirm(t.startTitle(port.name), `${time}${space} ${t.startBody}`, t.start))) return;
    report(await startJob(port.id, action, iso, bios, true));
    await reload();
  };

  const follow = async () => {
    const found = await adopt(port.id, "");
    if (found.ok) return reload();
    toaster.toast({ title: port.name, body: t.notFound });
    const folder = await pick(FileSelectionType.FOLDER, home);
    if (!folder) return;
    report(await adopt(port.id, folder));
    await reload();
  };

  const remove = async () => {
    if (!(await confirm(t.uninstallTitle(port.name), t.uninstallBody(port.name), t.uninstall, true))) return;
    if (!report(await uninstall(port.id))) return;
    for (const id of [port.steam_appid, port.legacy_appid]) {
      try {
        if (id && appStore()?.GetAppOverviewByAppID(id)) steamApps().RemoveShortcut(id);
      } catch {
        // already gone
      }
    }
    toaster.toast({ title: NAME, body: t.uninstalled(port.name) });
    await reload();
  };

  const rows = [];
  rows.push(
    <PanelSectionRow key="about">
      <Field description={[port.game, port.disc].filter(Boolean).join(" · ")} />
    </PanelSectionRow>,
  );

  if (running) {
    rows.push(
      <PanelSectionRow key="progress">
        <ProgressBarWithInfo
          indeterminate={job.percent === null}
          nProgress={job.percent ?? 0}
          sOperationText={job.stage}
          description={job.message}
        />
      </PanelSectionRow>,
      <PanelSectionRow key="stop">
        <ButtonItem layout="below" onClick={async () => (report(await cancelJob(port.id)), reload())}>
          {t.stop}
        </ButtonItem>
      </PanelSectionRow>,
    );
  } else if (job?.state === "failed") {
    rows.push(
      <PanelSectionRow key="failed">
        <Field description={`${t.failed(job.message)} ${t.log(job.log)}`} />
      </PanelSectionRow>,
    );
  }

  if (!port.supported) {
    rows.push(
      <PanelSectionRow key="launcher">
        <Field description={port.latest ? `${t.launcherOnly}. ${t.latest(port.latest.version)}.` : t.launcherOnly} />
      </PanelSectionRow>,
    );
  } else if (!port.installed && !running) {
    rows.push(
      <PanelSectionRow key="install">
        <ButtonItem layout="below" description={t.installHint} onClick={() => build("install", true)}>
          {t.install}
        </ButtonItem>
      </PanelSectionRow>,
      <PanelSectionRow key="adopt">
        <ButtonItem layout="below" description={t.alreadyHint} onClick={follow}>
          {t.alreadyInstalled}
        </ButtonItem>
      </PanelSectionRow>,
    );
  } else if (port.installed) {
    rows.push(
      <PanelSectionRow key="version">
        <Field description={versionLine(port)} />
      </PanelSectionRow>,
    );
    if (!running && !port.installed.built) {
      rows.push(
        <PanelSectionRow key="finish">
          <ButtonItem layout="below" onClick={() => build("install", !port.installed!.game_files)}>
            {t.rebuild}
          </ButtonItem>
        </PanelSectionRow>,
      );
    } else if (!running && port.update && port.latest) {
      rows.push(
        <PanelSectionRow key="update">
          <ButtonItem layout="below" onClick={() => build("update", !port.installed!.game_files)}>
            {t.update(port.latest.version)}
          </ButtonItem>
        </PanelSectionRow>,
      );
    }
    if (port.installed.built) {
      rows.push(
        <PanelSectionRow key="steam">
          {inSteam(port) ? (
            <Field description={t.inSteam} />
          ) : (
            <ButtonItem
              layout="below"
              onClick={async () => {
                await addToSteam(port.id, port.name, port.installed!.exe, port.installed!.start_dir);
                await reload();
              }}
            >
              {t.addToSteam}
            </ButtonItem>
          )}
        </PanelSectionRow>,
      );
    }
  }

  rows.push(
    <PanelSectionRow key="notes">
      <ButtonItem layout="below" onClick={() => Navigation.NavigateToExternalWeb(port.latest?.page ?? port.page)}>
        {port.latest ? t.releaseNotes : t.project}
      </ButtonItem>
    </PanelSectionRow>,
  );
  if (port.installed && !running) {
    rows.push(
      <PanelSectionRow key="uninstall">
        <ButtonItem layout="below" onClick={remove}>
          {t.uninstall}
        </ButtonItem>
      </PanelSectionRow>,
    );
  }
  return <>{rows}</>;
}

function Content() {
  const [state, setStateNow] = useState<State | undefined>(kept.state);
  const [open, setOpenNow] = useState<string | undefined>(kept.open);
  const setOpen = (id: string | undefined) => {
    kept.open = id;
    setOpenNow(id);
  };

  const reload = async () => {
    const reply = await getState();
    if (reply.ok) {
      kept.state = reply.result;
      setStateNow(reply.result);
    } else toaster.toast({ title: NAME, body: reply.error });
  };

  useEffect(() => {
    reload();
  }, []);

  // While a job runs its progress is read every couple of seconds.
  const busy = state?.ports.some((p) => p.job?.state === "running");
  useEffect(() => {
    const timer = setInterval(reload, busy ? 2000 : 15000);
    return () => clearInterval(timer);
  }, [busy]);

  const check = async () => {
    const reply = await checkUpdates(true);
    if (!reply.ok) toaster.toast({ title: NAME, body: reply.error });
    await reload();
    if (reply.ok && kept.state && !kept.state.ports.some((p) => p.update) && !kept.state.plugin)
      toaster.toast({ title: NAME, body: t.upToDate });
  };

  const updatePlugin = async () => {
    const reply = await downloadPlugin();
    if (reply.ok) await deckyInstall(reply.result);
    else toaster.toast({ title: NAME, body: reply.error });
  };

  if (!state) return null;
  const checked = state.checked ? new Date(state.checked * 1000).toLocaleString() : null;

  return (
    <>
      <PanelSection title={t.ports}>
        {state.ports.map((port) => [
          <PanelSectionRow key={port.id}>
            <ButtonItem
              layout="below"
              label={port.name}
              description={statusLine(port)}
              onClick={() => setOpen(open === port.id ? undefined : port.id)}
            >
              {open === port.id ? "▲" : "▼"}
            </ButtonItem>
          </PanelSectionRow>,
          open === port.id && <PortDetail key={`${port.id}-detail`} port={port} home={state.home} reload={reload} />,
        ])}
      </PanelSection>
      <PanelSection title={t.about}>
        {state.plugin && (
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={updatePlugin}>
              {t.pluginUpdate(state.plugin.version)}
            </ButtonItem>
          </PanelSectionRow>
        )}
        <PanelSectionRow>
          <ButtonItem layout="below" description={checked ? t.checked(checked) : t.never} onClick={check}>
            {t.check}
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <Field description={t.version(state.current)} />
        </PanelSectionRow>
      </PanelSection>
    </>
  );
}

// Told by the backend while the plugin is loaded, panel open or not.
async function onJobFinished(job: Job) {
  const name = job.name || job.id;
  if (job.state === "done") {
    toaster.toast({ title: NAME, body: t.ready(name) });
    const reply = await getState();
    const port = reply.ok ? reply.result.ports.find((p) => p.id === job.id) : undefined;
    if (job.add_to_steam && job.exe && job.start_dir && port && !inSteam(port))
      await addToSteam(job.id, name, job.exe, job.start_dir);
  } else if (job.state === "failed") {
    toaster.toast({ title: NAME, body: t.failedToast(name) });
  }
}

function onUpdate(news: { name: string; version: string }) {
  toaster.toast({ title: NAME, body: t.updateToast(news.name, news.version) });
}

type DeckyState = {
  _activePlugin?: { name: string } | null;
  _plugins?: { name: string }[];
  setActivePlugin?(name: string): void;
};

// After an update Decky loads the new plugin but keeps showing the old panel while it stays open
// (decky-loader issue 976). Once the new plugin is registered, open it in place of the old one.
function showNewPanel() {
  const state = (window as unknown as { DeckyPluginLoader?: { deckyState?: DeckyState } }).DeckyPluginLoader
    ?.deckyState;
  const active = state?._activePlugin;
  const loaded = state?._plugins?.find((plugin) => plugin.name === NAME);
  if (active?.name === NAME && loaded && loaded !== active) state?.setActivePlugin?.(NAME);
}

export default definePlugin(() => {
  setTimeout(showNewPanel, 1000);
  const finished = addEventListener<[Job]>("job_finished", onJobFinished);
  const update = addEventListener<[{ name: string; version: string }]>("update_available", onUpdate);
  return {
    name: NAME,
    titleView: <div className={staticClasses.Title}>{NAME}</div>,
    content: <Content />,
    icon: <FaGamepad />,
    alwaysRender: true,
    onDismount() {
      removeEventListener("job_finished", finished);
      removeEventListener("update_available", update);
    },
  };
});
