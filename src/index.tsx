import { ButtonItem, Field, PanelSection, PanelSectionRow, Router, staticClasses } from "@decky/ui";
import { addEventListener, callable, definePlugin, removeEventListener, toaster } from "@decky/api";
import { useEffect, useState } from "react";
import { FaGamepad } from "react-icons/fa";
import { t } from "./i18n";

// The ports are browsed, installed and played from the Armada Ports app, a game in the Steam
// library. This plugin is what the app cannot be: a part of Steam. It puts the app (and the games
// the app builds) in the library with their artwork at once, without restarting Steam, answers the
// app's requests for that, tells about finished builds and new releases, and updates itself.

type Art = Partial<Record<"grid" | "hero" | "logo" | "wide", string>>;
type Shortcut = { port: string; name: string; exe: string; start_dir: string; art: Art };
type Job = {
  id: string;
  state: "running" | "done" | "failed" | "cancelled";
  stage: string;
  percent: number | null;
  add_to_steam?: boolean;
  name?: string;
};
type Port = {
  id: string;
  name: string;
  update: boolean;
  latest: { version: string } | null;
  job: Job | null;
  steam_appid: number | null;
  legacy_appid: number | null;
  installed: { built: boolean } | null;
};
type State = { ports: Port[]; checked: number | null; plugin: { version: string } | null; current: string };
type AppInfo = {
  installed: boolean;
  name: string;
  exe: string;
  start_dir: string;
  art: Art;
  appid: number | null;
  offered: boolean;
  version: string;
};
type BridgeRequest =
  | { id: string; op: "steam_status"; ports: { id: string; appids: number[] }[] }
  | { id: string; op: "add_shortcut"; port: string; shortcut: Shortcut }
  | { id: string; op: "remove_shortcut"; appids: number[] };
type Reply<T> = { ok: true; result: T } | { ok: false; error: string };
type BridgeReply = { ok: boolean; result?: unknown; error?: string };
type PluginDownload = { path: string; version: string; sha256: string };

const getState = callable<[], Reply<State>>("get_state");
const checkUpdates = callable<[refresh: boolean], Reply<{ news: unknown[] }>>("check_updates");
const setSteam = callable<[port: string, appid: number], Reply<null>>("set_steam");
const appInfo = callable<[], Reply<AppInfo>>("app_info");
const rememberApp = callable<[appid: number], Reply<null>>("remember_app");
const shortcutFor = callable<[port: string], Reply<Shortcut>>("shortcut_for");
const readImage = callable<[path: string], Reply<{ data: string; format: string }>>("read_image");
const bridgeReply = callable<[id: string, reply: BridgeReply], Reply<null>>("bridge_reply");
const downloadPlugin = callable<[], Reply<PluginDownload>>("download_plugin");

const NAME = "Armada Ports";
const ART_TYPES: Record<keyof Art, number> = { grid: 0, hero: 1, logo: 2, wide: 3 };

type SteamApps = {
  AddShortcut(name: string, exe: string, startDir: string, launchOptions: string): Promise<number>;
  SetShortcutName(appid: number, name: string): void;
  SetShortcutExe(appid: number, exe: string): void;
  SetShortcutStartDir(appid: number, dir: string): void;
  RemoveShortcut(appid: number): void;
  SetCustomArtworkForApp(appid: number, data: string, format: string, assetType: number): Promise<unknown>;
  RunGame(gameId: string, launchSource: string, a: number, b: number): void;
};
type Overview = { m_gameid?: string; gameid?: string };
const steamApps = () => (window as unknown as { SteamClient: { Apps: SteamApps } }).SteamClient.Apps;
const appStore = () =>
  (window as unknown as { appStore?: { GetAppOverviewByAppID(id: number): Overview | null } }).appStore;

const inLibrary = (appid: number | null | undefined) => !!appid && !!appStore()?.GetAppOverviewByAppID(appid);

async function setArtwork(appid: number, art: Art) {
  for (const kind of Object.keys(ART_TYPES) as (keyof Art)[]) {
    const path = art[kind];
    if (!path) continue;
    const image = await readImage(path);
    if (image.ok) await steamApps().SetCustomArtworkForApp(appid, image.result.data, image.result.format, ART_TYPES[kind]);
  }
}

// A non-Steam game, added through Steam itself: it shows up at once, no restart needed.
async function addShortcut(name: string, exe: string, startDir: string, art: Art): Promise<number> {
  const apps = steamApps();
  const appid = await apps.AddShortcut(name, exe, startDir, "");
  if (!appid) throw new Error(t.steamFailed);
  apps.SetShortcutName(appid, name);
  apps.SetShortcutExe(appid, `"${exe}"`);
  apps.SetShortcutStartDir(appid, `"${startDir}"`);
  try {
    await setArtwork(appid, art);
  } catch {
    // the game is in the library; artwork is a nicety
  }
  return appid;
}

async function addPort(shortcut: Shortcut): Promise<number> {
  const appid = await addShortcut(shortcut.name, shortcut.exe, shortcut.start_dir, shortcut.art);
  await setSteam(shortcut.port, appid);
  return appid;
}

async function answer(req: BridgeRequest): Promise<BridgeReply> {
  switch (req.op) {
    case "steam_status": {
      const result: Record<string, number> = {};
      for (const port of req.ports) result[port.id] = port.appids.find(inLibrary) ?? 0;
      return { ok: true, result };
    }
    case "add_shortcut": {
      const appid = await addPort(req.shortcut);
      toaster.toast({ title: NAME, body: t.addedToSteam(req.shortcut.name) });
      return { ok: true, result: { appid } };
    }
    case "remove_shortcut": {
      for (const appid of req.appids) if (inLibrary(appid)) steamApps().RemoveShortcut(appid);
      return { ok: true, result: null };
    }
  }
  return { ok: false, error: "unknown request" };
}

async function onBridgeRequest(req: BridgeRequest) {
  let reply: BridgeReply;
  try {
    reply = await answer(req);
  } catch (e) {
    reply = { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
  await bridgeReply(req.id, reply);
}

// Puts the app in the library the first time (and when asked again from the panel).
async function ensureApp(ask = false): Promise<number | null> {
  const reply = await appInfo();
  if (!reply.ok || !reply.result.installed) return null;
  const app = reply.result;
  if (inLibrary(app.appid)) return app.appid;
  if (app.offered && !ask) return null;
  try {
    const appid = await addShortcut(app.name, app.exe, app.start_dir, app.art);
    await rememberApp(appid);
    toaster.toast({ title: NAME, body: t.appAdded });
    return appid;
  } catch (e) {
    await rememberApp(0);
    toaster.toast({ title: NAME, body: `${t.steamFailed} ${e}` });
    return null;
  }
}

function gameIdOf(appid: number): string {
  const overview = appStore()?.GetAppOverviewByAppID(appid);
  const known = overview?.m_gameid ?? overview?.gameid;
  if (known) return String(known);
  return (BigInt(appid) * BigInt(4294967296) + BigInt(0x02000000)).toString();
}

async function openApp() {
  const appid = await ensureApp(true);
  if (!appid) return;
  Router.CloseSideMenus();
  steamApps().RunGame(gameIdOf(appid), "", -1, 100);
}

// Decky's own installer: it asks for confirmation, replaces the plugin and reloads it.
const UPDATE = 2;
function deckyInstall(update: PluginDownload) {
  const backend = (window as unknown as { DeckyBackend: { call(route: string, ...args: unknown[]): Promise<unknown> } })
    .DeckyBackend;
  return backend.call("utilities/install_plugin", `file://${update.path}`, NAME, update.version, update.sha256, UPDATE);
}

function jobLine(job: Job): string {
  return job.percent === null ? job.stage : `${job.stage} · ${Math.round(job.percent)}%`;
}

function Content() {
  const [state, setState] = useState<State>();
  const [app, setApp] = useState<AppInfo>();

  const reload = async () => {
    const [s, a] = await Promise.all([getState(), appInfo()]);
    if (s.ok) setState(s.result);
    else toaster.toast({ title: NAME, body: s.error });
    if (a.ok) setApp(a.result);
  };

  useEffect(() => {
    reload();
  }, []);

  const busy = state?.ports.some((p) => p.job?.state === "running");
  useEffect(() => {
    const timer = setInterval(reload, busy ? 3000 : 15000);
    return () => clearInterval(timer);
  }, [busy]);

  const check = async () => {
    const reply = await checkUpdates(true);
    if (!reply.ok) toaster.toast({ title: NAME, body: reply.error });
    await reload();
    if (reply.ok && reply.result.news.length === 0) toaster.toast({ title: NAME, body: t.upToDate });
  };

  const updatePlugin = async () => {
    const reply = await downloadPlugin();
    if (reply.ok) await deckyInstall(reply.result);
    else toaster.toast({ title: NAME, body: reply.error });
  };

  if (!state) return null;
  const running = state.ports.filter((p) => p.job?.state === "running");
  const updates = state.ports.filter((p) => p.update && p.latest);
  const checked = state.checked ? new Date(state.checked * 1000).toLocaleString() : null;

  return (
    <>
      <PanelSection>
        <PanelSectionRow>
          <ButtonItem layout="below" onClick={openApp} disabled={!app?.installed}>
            {inLibrary(app?.appid) ? t.openApp : t.addApp}
          </ButtonItem>
        </PanelSectionRow>
        <PanelSectionRow>
          <Field description={app?.installed ? t.blurb : t.noApp} />
        </PanelSectionRow>
      </PanelSection>
      {running.length > 0 && (
        <PanelSection title={t.building}>
          {running.map((p) => (
            <PanelSectionRow key={p.id}>
              <Field label={p.name} description={jobLine(p.job as Job)} />
            </PanelSectionRow>
          ))}
        </PanelSection>
      )}
      {updates.length > 0 && (
        <PanelSection title={t.updates}>
          {updates.map((p) => (
            <PanelSectionRow key={p.id}>
              <Field label={p.name} description={t.newVersion(p.latest!.version)} />
            </PanelSectionRow>
          ))}
        </PanelSection>
      )}
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
    if (job.add_to_steam && port && !inLibrary(port.steam_appid) && !inLibrary(port.legacy_appid)) {
      const shortcut = await shortcutFor(job.id);
      if (shortcut.ok) {
        try {
          await addPort(shortcut.result);
          toaster.toast({ title: NAME, body: t.addedToSteam(shortcut.result.name) });
        } catch (e) {
          toaster.toast({ title: NAME, body: `${t.steamFailed} ${e}` });
        }
      }
    }
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
  // Give Steam a moment after starting before touching the library.
  setTimeout(() => ensureApp(false), 8000);
  const finished = addEventListener<[Job]>("job_finished", onJobFinished);
  const update = addEventListener<[{ name: string; version: string }]>("update_available", onUpdate);
  const bridge = addEventListener<[BridgeRequest]>("bridge_request", onBridgeRequest);
  return {
    name: NAME,
    titleView: <div className={staticClasses.Title}>{NAME}</div>,
    content: <Content />,
    icon: <FaGamepad />,
    alwaysRender: true,
    onDismount() {
      removeEventListener("job_finished", finished);
      removeEventListener("update_available", update);
      removeEventListener("bridge_request", bridge);
    },
  };
});
