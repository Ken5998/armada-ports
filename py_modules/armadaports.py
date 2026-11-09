"""Armada Ports: the catalog of ARM64 ports, what of it is installed, their GitHub releases and
the jobs that install or update a port.

The Decky backend (main.py) imports this module. A job runs it again as a separate program,
`python3 armadaports.py run JOB.json`, started with systemd-run in the user's session so that a
build of an hour survives the Quick Access menu closing, a game starting or Decky reloading.
The job writes its progress to JOB.json; the panel reads it from there.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
import zlib

CHECK_MAX_AGE = 6 * 3600          # GitHub allows 60 unauthenticated requests an hour
PLUGIN_REPO = 'Ken5998/armada-ports'
PROGRESS = re.compile(r'^\[(\d+)/(\d+)\]')   # ninja and cmake progress


class PortsError(Exception):
    """A problem to show in the panel as it is."""


# --- Places -----------------------------------------------------------------------------

def paths(home):
    share = os.path.join(home, '.local', 'share')
    root = os.path.join(share, 'armada-ports')
    return {
        'home': home,
        'share': share,
        'root': root,
        'state': os.path.join(root, 'state.json'),
        'jobs': os.path.join(root, 'jobs'),
        'logs': os.path.join(root, 'logs'),
        'launchers': os.path.join(root, 'launchers'),
        'cache': os.path.join(root, 'cache'),
    }


def write(path, text):
    """Writes a whole file at once: a reader never sees half of it."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f'{path}.tmp-{os.getpid()}'
    with open(tmp, 'w') as f:
        f.write(text)
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def load_catalog(plugin_dir):
    data = read_json(os.path.join(plugin_dir, 'ports.json'))
    if not isinstance(data, dict) or not isinstance(data.get('ports'), list):
        raise PortsError('ports.json is missing or broken: reinstall the plugin.')
    return data['ports']


def find_port(plugin_dir, port_id):
    for port in load_catalog(plugin_dir):
        if port['id'] == port_id:
            return port
    raise PortsError(f'Unknown port: {port_id}')


def load_state(p):
    state = read_json(p['state'], {})
    if not isinstance(state, dict):
        state = {}
    state.setdefault('ports', {})
    state.setdefault('latest', {})
    return state


def save_state(p, state):
    write(p['state'], json.dumps(state, indent=2))


def record(p, port_id, **values):
    """Changes the saved facts about one port; None removes a fact."""
    state = load_state(p)
    entry = state['ports'].setdefault(port_id, {})
    for key, value in values.items():
        if value is None:
            entry.pop(key, None)
        else:
            entry[key] = value
    save_state(p, state)
    return entry


# --- Versions and downloads ----------------------------------------------------------------

def version_key(text):
    """0.10.2 > 0.9.0; anything after a '-' ranks the version below its release."""
    text = str(text or '').strip().lstrip('vV')
    core, _, pre = text.partition('-')
    numbers = [int(n) if n.isdigit() else 0 for n in core.split('.')[:3]]
    numbers += [0] * (3 - len(numbers))
    return (*numbers, 0 if pre else 1)


def ssl_context():
    import ssl
    try:
        import certifi  # Decky's backend ships it; the system store may be out of its reach.
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


def open_url(url, timeout=30):
    import urllib.request
    request = urllib.request.Request(url, headers={'User-Agent': 'armada-ports',
                                                   'Accept': 'application/vnd.github+json'})
    kwargs = {'context': ssl_context()} if url.startswith('https:') else {}
    try:
        return urllib.request.urlopen(request, timeout=timeout, **kwargs)
    except OSError as e:
        raise PortsError(f'Could not reach GitHub: {getattr(e, "reason", e)}') from e


def download(url, dst, sha256=None, progress=None):
    """Downloads to dst; checks the SHA-256 GitHub lists for the asset when there is one."""
    digest = hashlib.sha256()
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try:
        with open_url(url, timeout=60) as response, open(dst, 'wb') as f:
            total = int(response.headers.get('Content-Length') or 0)
            done = 0
            while chunk := response.read(1 << 20):
                digest.update(chunk)
                f.write(chunk)
                done += len(chunk)
                if progress and total:
                    progress(done * 100 / total)
    except OSError as e:
        raise PortsError(f'Download failed: {e}') from e
    if sha256 and digest.hexdigest() != sha256:
        os.remove(dst)
        raise PortsError('The download does not match its checksum; nothing was changed.')


def asset_sha256(asset):
    digest = asset.get('digest') or ''
    return digest[7:] if digest.startswith('sha256:') and len(digest) == 71 else None


def latest_release(repo, asset_name):
    """The newest published release of a repository and its launcher asset."""
    with open_url(f'https://api.github.com/repos/{repo}/releases/latest') as response:
        rel = json.load(response)
    if not isinstance(rel, dict) or 'tag_name' not in rel:
        raise PortsError(f'{repo} has no release yet.')
    tag = str(rel['tag_name'])
    version = tag.lstrip('vV')
    wanted = asset_name.replace('{version}', version) if asset_name else None
    asset = next((a for a in rel.get('assets') or [] if a.get('name') == wanted), None)
    return {
        'tag': tag,
        'version': version,
        'url': asset['browser_download_url'] if asset else None,
        'sha256': asset_sha256(asset) if asset else None,
        'size': asset.get('size', 0) if asset else 0,
        'page': rel.get('html_url') or f'https://github.com/{repo}/releases/tag/{tag}',
        'published': rel.get('published_at') or '',
    }


def git_head(repo_url):
    """The commit main points at now, or None offline."""
    try:
        out = subprocess.run(['git', 'ls-remote', repo_url, 'refs/heads/main'], capture_output=True,
                             text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.match(r'([0-9a-f]{40})\s', out.stdout)
    return m.group(1) if m else None


def shortcut_app_id(exe, name):
    """The id Steam gives a non-Steam game (as the launchers' add-to-Steam scripts compute it)."""
    return zlib.crc32(f'"{exe}"{name}'.encode('utf-8')) | 0x80000000


def free_space(path):
    while path and not os.path.exists(path):
        path = os.path.dirname(path)
    try:
        st = os.statvfs(path or '/')
        return st.f_bavail * st.f_frsize
    except OSError:
        return None


# --- What a port is like on this device ------------------------------------------------------

class Adapter:
    """How the plugin finds, installs and updates one port. A port without its own adapter is
    listed with its newest release only: install it with its launcher for now."""
    supported = False
    name = ''

    def __init__(self, p, port, entry):
        self.p, self.port, self.entry = p, port, entry

    @property
    def launcher_dir(self):
        """The launcher's folder: the one picked in the panel, else the plugin's own copy."""
        return self.entry.get('launcher_dir') or os.path.join(self.p['launchers'], self.port['id'])

    def launcher_installed(self):
        name = self.port.get('launcher')
        return bool(name) and os.path.isfile(os.path.join(self.launcher_dir, name))

    def detect(self):
        return None

    def extra_latest(self):
        return {}

    def update_available(self, info, latest):
        return bool(info and latest and info.get('version') and
                    version_key(latest['version']) > version_key(info['version']))

    def adopt(self, folder):
        raise PortsError('Install it with its launcher for now.')

    def build(self, job, iso, bios):
        raise PortsError('This port cannot be installed from the plugin yet.')

    def remove(self):
        raise PortsError('Remove it as its README says.')


class Pinyon(Adapter):
    """Pinyon Shift: upstream's launcher with this repository's source payload. The launcher's work
    is tools/pinyon.py in the payload, so the plugin runs that, as the launcher does."""
    supported = True
    name = 'Pinyon Shift'

    def install_root(self):
        base = os.path.join(self.p['share'], 'PinyonShift')
        try:
            with open(os.path.join(base, 'install-root.txt')) as f:
                chosen = f.read().strip()
            if chosen:
                return chosen
        except OSError:
            pass
        return base

    @staticmethod
    def is_source(path):
        return all(os.path.isfile(os.path.join(path, f)) for f in ('config/release.json', 'tools/pinyon.py'))

    def source(self):
        known = self.entry.get('source')
        if known and self.is_source(known):
            return known
        found = [d for d in glob.glob(os.path.join(self.install_root(), 'source', '*')) if self.is_source(d)]
        return max(found, key=os.path.getmtime) if found else None

    def detect(self):
        src = self.source()
        if not src:
            return None
        release = read_json(os.path.join(src, 'config/release.json'), {})
        built = bool(glob.glob(os.path.join(src, 'out/build/*-release/pinyon_shift')))
        return {
            'data': src,
            'version': str(release.get('version') or ''),
            'built': built,
            'game_files': os.path.isfile(os.path.join(src, '.local/game/base/default.xex')),
            'exe': os.path.join(src, '.local/pinyon-shift.sh'),
            'start_dir': src,
        }

    def adopt(self, folder):
        if folder and os.path.isfile(os.path.join(folder, 'PinyonShiftLauncher')):
            return {'launcher_dir': folder}
        if folder and self.is_source(folder):
            return {'source': folder}
        if folder:
            raise PortsError('That folder has neither PinyonShiftLauncher nor the Pinyon Shift source.')
        return {}

    # The launcher unpacks into source/<its assembly version>. That version is fixed in upstream's
    # project (0.1.1) and does not follow the releases; it cannot be read from the bundled binary.
    SOURCE_VERSION = '0.1.1'

    def source_folder(self):
        """Where the launcher keeps the source: the folder already there, else the one it would make."""
        current = self.source()
        if current and os.path.dirname(current) == os.path.join(self.install_root(), 'source'):
            return current
        return os.path.join(self.install_root(), 'source', self.SOURCE_VERSION)

    def build(self, job, iso, bios):
        payload = os.path.join(self.launcher_dir, 'pinyon-shift-source.zip')
        if not os.path.isfile(payload):
            raise PortsError(f'No pinyon-shift-source.zip in {self.launcher_dir}.')
        dest = self.source_folder()
        job.stage('Unpacking the source')
        written = extract_pinyon_payload(payload, dest)
        job.line(f'Source in {dest} ({written} files changed)')
        record(self.p, self.port['id'], source=dest)
        self.entry['source'] = dest
        if iso:
            args = ['--extracted' if os.path.isdir(iso) else '--iso', iso]
        elif os.path.isfile(os.path.join(dest, '.local/game/base/default.xex')):
            args = ['--build-only']
        else:
            raise PortsError('The game files are not extracted yet: pick your disc image.')
        python = shutil.which('python3') or '/usr/bin/python3'
        env = dict(os.environ, PYTHONUNBUFFERED='1', PYTHONUTF8='1')
        job.stage('Building Pinyon Shift')
        job.run([python, os.path.join(dest, 'tools', 'pinyon.py'), 'setup', '--json', *args], cwd=dest, env=env,
                parse=pinyon_event)
        job.stage('Writing the start script')
        job.run([python, os.path.join(dest, 'tools', 'pinyon.py'), 'shortcuts', 'add', '--no-steam', '--no-desktop'],
                cwd=dest, env=env)

    def remove(self):
        base = os.path.join(self.p['share'], 'PinyonShift')
        root = self.install_root()
        # The default folder holds nothing else; a folder picked in the launcher may.
        if os.path.realpath(root) == os.path.realpath(base):
            return [base] if os.path.isdir(base) else []
        src = self.source()
        return [src] if src else []


def pinyon_event(job, line):
    """::pinyon::{"stage": ..., "percent": ..., "message": ..., "error": ...} from tools/pinyon.py."""
    if not line.startswith('::pinyon::'):
        return False
    try:
        event = json.loads(line[len('::pinyon::'):])
    except ValueError:
        return False
    if event.get('error'):
        job.update(message=str(event['error']))
    percent = event.get('percent')
    job.update(stage=str(event.get('stage') or job.data.get('stage') or ''),
               percent=float(percent) if isinstance(percent, (int, float)) and percent >= 0 else None,
               message=str(event.get('message') or job.data.get('message') or ''))
    return True


def extract_pinyon_payload(payload, dest):
    """Unpacks the source payload as the launcher does (Installation.OpenAsync): removes the files
    the previous payload listed and this one dropped, writes only files whose bytes changed (with
    the current time, so the build sees them as new), then the hash marker and the file list."""
    digest = hashlib.sha256()
    with open(payload, 'rb') as f:
        while chunk := f.read(1 << 20):
            digest.update(chunk)
    sha = digest.hexdigest().upper()
    marker = os.path.join(dest, '.pinyon-source-sha256')
    manifest = os.path.join(dest, '.pinyon-source-files')
    root = os.path.realpath(dest) + os.sep
    with zipfile.ZipFile(payload) as z:
        entries = sorted(i.filename.replace('\\', '/') for i in z.infolist() if not i.is_dir())
        try:
            with open(marker) as f:
                same = f.read().strip().upper() == sha
        except OSError:
            same = False
        if same and Pinyon.is_source(dest):
            if not os.path.isfile(manifest):
                write(manifest, '\n'.join(entries) + '\n')
            return 0
        os.makedirs(dest, exist_ok=True)
        keep = {e.lower() for e in entries}
        try:
            with open(manifest) as f:
                old = [line.strip().replace('\\', '/') for line in f]
        except OSError:
            old = []
        for rel in old:
            if not rel or rel.lower() in keep or rel.split('/')[0] in ('.local', 'out', '..') or rel.startswith('/'):
                continue
            path = os.path.realpath(os.path.join(dest, rel))
            if path.startswith(root) and os.path.isfile(path):
                os.remove(path)
        written = 0
        for info in z.infolist():
            path = os.path.realpath(os.path.join(dest, info.filename))
            if not (path + os.sep).startswith(root):
                raise PortsError(f'The payload entry {info.filename} points outside the source folder.')
            if info.is_dir():
                os.makedirs(path, exist_ok=True)
                continue
            if os.path.isfile(path) and os.path.getsize(path) == info.file_size:
                with open(path, 'rb') as f:
                    if f.read() == z.read(info):
                        continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with z.open(info) as src, open(path, 'wb') as out:
                shutil.copyfileobj(src, out)
            mode = (info.external_attr >> 16) & 0o777
            if mode:
                os.chmod(path, mode)
            written += 1
    if not Pinyon.is_source(dest):
        raise PortsError('The source payload is incomplete. Download the launcher again.')
    write(marker, sha + '\n')
    write(manifest, '\n'.join(entries) + '\n')
    return written


class Fifa(Adapter):
    """FIFA Street: the launcher builds with this repository's scripts from a git clone it keeps up
    to date (overlay/), so a new commit on main is an update as much as a new launcher release."""
    supported = True
    name = 'FIFA Street'
    REPO_URL = 'https://github.com/Ken5998/fifa-street-arm64'

    @property
    def data(self):
        return os.path.join(self.p['share'], 'FifaStreet-arm64')

    def overlay_commit(self):
        try:
            out = subprocess.run(['git', '-C', os.path.join(self.data, 'overlay'), 'rev-parse', 'HEAD'],
                                 capture_output=True, text=True, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return out.stdout.strip() if out.returncode == 0 else None

    def launcher_version(self):
        if not self.launcher_installed():
            return self.entry.get('launcher_version')
        try:
            out = subprocess.run([os.path.join(self.launcher_dir, 'fifastreet-launcher'), '--version'],
                                 capture_output=True, text=True, timeout=10)
            return out.stdout.strip() or None
        except (OSError, subprocess.TimeoutExpired):
            return None

    def detect(self):
        game = os.path.join(self.data, 'game', 'fifastreet.sh')
        commit = self.overlay_commit()
        if not commit and not os.path.isfile(game):
            return None
        launcher = self.launcher_version()
        return {
            'data': self.data,
            'version': launcher or '',
            'commit': commit or '',
            'built': os.path.isfile(game),
            'game_files': os.path.isfile(os.path.join(self.data, 'GameData', 'default.xex')),
            'exe': game,
            'start_dir': os.path.dirname(game),
        }

    def extra_latest(self):
        head = git_head(self.REPO_URL)
        return {'commit': head} if head else {}

    def update_available(self, info, latest):
        if not info or not latest:
            return False
        if latest.get('commit') and info.get('commit') and latest['commit'] != info['commit']:
            return True
        return super().update_available(info, latest)

    def adopt(self, folder):
        if folder and os.path.isfile(os.path.join(folder, 'fifastreet-launcher')):
            return {'launcher_dir': folder}
        if folder:
            raise PortsError('That folder has no fifastreet-launcher.')
        return {}

    def build(self, job, iso, bios):
        overlay = os.path.join(self.data, 'overlay')
        job.stage('Updating the scripts and patches')
        if os.path.isdir(os.path.join(overlay, '.git')):
            job.run(['git', '-C', overlay, 'fetch', '--depth', '50', 'origin', 'main'])
            job.run(['git', '-C', overlay, 'reset', '--hard', '-q', 'FETCH_HEAD'])
        else:
            os.makedirs(self.data, exist_ok=True)
            shutil.rmtree(overlay, ignore_errors=True)
            job.run(['git', 'clone', '-q', '--depth', '50', self.REPO_URL, overlay])
        if not iso and not os.path.isfile(os.path.join(self.data, 'GameData', 'default.xex')):
            raise PortsError('The game files are not extracted yet: pick your disc image.')
        job.stage('Building FIFA Street (an hour or more)')
        job.run(['bash', os.path.join(overlay, 'scripts', 'build.sh'), iso or '-', self.data],
                env=dict(os.environ, FS_ADD_TO_STEAM='0'), parse=step_event)

    def remove(self):
        return [self.data] if os.path.isdir(self.data) else []


def step_event(job, line):
    """`==> [12:00:00] Step` lines from the build scripts start a stage; [n/m] lines are progress."""
    m = re.match(r'^==> \[[0-9:]+\] (.+)$', line)
    if m:
        job.update(stage=m.group(1), percent=None)
        return False
    m = PROGRESS.match(line)
    if m and int(m.group(2)) > 0:
        job.update(percent=int(m.group(1)) * 100 / int(m.group(2)))
    return False


ADAPTERS = {'pinyon': Pinyon, 'fifa': Fifa}


def adapter_for(p, port, state=None):
    state = state or load_state(p)
    entry = state['ports'].get(port['id'], {})
    return ADAPTERS.get(port.get('adapter') or '', Adapter)(p, port, entry)


# --- The panel's view ---------------------------------------------------------------------

def port_view(p, port, state):
    a = adapter_for(p, port, state)
    entry = state['ports'].get(port['id'], {})
    info = a.detect() if a.supported else None
    latest = state['latest'].get(port['id'])
    job = job_status(p, port['id'])
    view = {
        'id': port['id'],
        'name': port['name'],
        'game': port.get('game', ''),
        'repo': port['repo'],
        'page': f'https://github.com/{port["repo"]}',
        'supported': a.supported,
        'needs': port.get('needs', []),
        'disc': port.get('disc', ''),
        'build_minutes': port.get('build_minutes'),
        'space_gb': port.get('space_gb'),
        'free_gb': None,
        'installed': info,
        'latest': latest,
        'update': a.update_available(info, latest) if info else False,
        'job': job,
        'launcher_dir': a.launcher_dir if a.launcher_installed() else None,
        'steam_appid': entry.get('steam_appid'),
        'legacy_appid': None,
    }
    if info and info.get('exe'):
        view['legacy_appid'] = shortcut_app_id(info['exe'], a.name)
    space = free_space(p['share'])
    if space is not None:
        view['free_gb'] = round(space / (1 << 30), 1)
    return view


def overview(p, plugin_dir):
    state = load_state(p)
    return {
        'home': p['home'],
        'ports': [port_view(p, port, state) for port in load_catalog(plugin_dir)],
        'checked': state.get('checked'),
        'plugin': state.get('plugin'),
    }


def check_updates(p, plugin_dir, refresh=False, current=None):
    """Looks up every port's newest release (at most every few hours unless refresh) and returns
    the updates nobody was told about yet, which it then marks as told."""
    state = load_state(p)
    if not refresh and time.time() - float(state.get('checked') or 0) < CHECK_MAX_AGE:
        return {'news': [], 'plugin': state.get('plugin')}
    errors = []
    for port in load_catalog(plugin_dir):
        try:
            latest = latest_release(port['repo'], port.get('asset'))
            latest.update(adapter_for(p, port, state).extra_latest())
            state['latest'][port['id']] = latest
        except PortsError as e:
            errors.append(f'{port["name"]}: {e}')
    try:
        mine = latest_release(PLUGIN_REPO, 'ArmadaPorts-v{version}.zip')
        newer = current and mine['url'] and version_key(mine['version']) > version_key(current)
        state['plugin'] = mine if newer else None
    except PortsError:
        state['plugin'] = None
    state['checked'] = time.time()
    save_state(p, state)
    news = []
    for port in load_catalog(plugin_dir):
        view = port_view(p, port, state)
        if not view['update']:
            continue
        latest = view['latest']
        mark = f'{latest.get("version")}@{latest.get("commit", "")}'
        entry = state['ports'].setdefault(port['id'], {})
        if entry.get('told') != mark:
            entry['told'] = mark
            news.append({'id': port['id'], 'name': port['name'], 'version': latest.get('version')})
    save_state(p, state)
    if errors and len(errors) == len(load_catalog(plugin_dir)):
        raise PortsError(errors[0])
    return {'news': news, 'plugin': state.get('plugin')}


def adopt(p, plugin_dir, port_id, folder=None):
    """'It is already installed': finds the port in its usual place, or takes the folder picked."""
    port = find_port(plugin_dir, port_id)
    a = adapter_for(p, port)
    if not a.supported:
        raise PortsError('This port cannot be followed from the plugin yet.')
    values = a.adopt(folder or None)
    a.entry.update(values)
    if not a.detect():
        raise PortsError('Not found where its launcher installs it. Pick the launcher folder, or install it.')
    record(p, port_id, adopted=True, **values)
    return port_view(p, port, load_state(p))


def set_steam(p, port_id, appid):
    record(p, port_id, steam_appid=int(appid) if appid else None)


def uninstall(p, plugin_dir, port_id):
    """Removes the game this port built (with its saves) and the plugin's copy of its launcher."""
    port = find_port(plugin_dir, port_id)
    a = adapter_for(p, port)
    job = job_status(p, port_id)
    if job and job['state'] == 'running':
        raise PortsError('A job is running for this port; stop it first.')
    removed = a.remove()
    own = os.path.join(p['launchers'], port_id)
    if os.path.isdir(own):
        removed.append(own)
    for path in removed:
        shutil.rmtree(path, ignore_errors=True)
    state = load_state(p)
    state['ports'].pop(port_id, None)
    save_state(p, state)
    return removed


# --- Jobs ---------------------------------------------------------------------------------

def job_file(p, port_id):
    return os.path.join(p['jobs'], f'{port_id}.json')


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def job_status(p, port_id):
    """The port's last job; a running job whose process is gone is reported as failed."""
    data = read_json(job_file(p, port_id))
    if not isinstance(data, dict):
        return None
    if data.get('state') == 'running':
        pid = data.get('pid')
        late = time.time() - float(data.get('started') or 0) > 60
        if (pid and not alive(pid)) or (not pid and late):
            data.update(state='failed', message=data.get('message') or 'The job stopped unexpectedly.',
                        finished=time.time())
            write(job_file(p, port_id), json.dumps(data))
    return data


def start_job(p, plugin_dir, port_id, action, iso=None, bios=None, add_to_steam=True):
    port = find_port(plugin_dir, port_id)
    a = adapter_for(p, port)
    if not a.supported:
        raise PortsError('This port cannot be installed from the plugin yet: use its launcher.')
    current = job_status(p, port_id)
    if current and current['state'] == 'running':
        raise PortsError('A job is already running for this port.')
    if iso and not os.path.exists(iso):
        raise PortsError(f'Not found: {iso}')
    space = free_space(p['share'])
    need = port.get('space_gb')
    if action == 'install' and need and space is not None and space < need * (1 << 30):
        raise PortsError(f'About {need} GB free are needed; there are {space / (1 << 30):.0f} GB.')
    state = load_state(p)
    latest = state['latest'].get(port_id)
    if not latest:
        latest = latest_release(port['repo'], port.get('asset'))
    os.makedirs(p['logs'], exist_ok=True)
    log = os.path.join(p['logs'], f'{port_id}-{time.strftime("%Y%m%d-%H%M%S")}.log')
    unit = f'armada-ports-{port_id}-{int(time.time())}'
    job = {
        'id': port_id, 'action': action, 'state': 'running', 'stage': 'Starting', 'percent': None,
        'message': '', 'log': log, 'started': time.time(), 'finished': None, 'pid': None, 'unit': unit,
        'iso': iso or None, 'bios': bios or None, 'add_to_steam': bool(add_to_steam),
        'home': p['home'], 'plugin_dir': plugin_dir, 'release': latest, 'announced': False,
    }
    path = job_file(p, port_id)
    write(path, json.dumps(job))
    spawn(path, unit, log)
    return job


def user_env():
    env = dict(os.environ)
    uid = os.getuid()
    env.setdefault('XDG_RUNTIME_DIR', f'/run/user/{uid}')
    env.setdefault('DBUS_SESSION_BUS_ADDRESS', f'unix:path=/run/user/{uid}/bus')
    # Decky's backend is a bundled Python; the job wants the system's own libraries.
    for key in ('LD_LIBRARY_PATH', 'PYTHONHOME', 'PYTHONPATH', 'SSL_CERT_FILE'):
        env.pop(key, None)
    return env


def spawn(path, unit, log):
    """Starts the job in the user's systemd session (outside Decky's service, so it outlives it),
    else as a detached process."""
    python = shutil.which('python3', path='/usr/bin:/usr/local/bin') or 'python3'
    script = os.path.abspath(__file__)
    env = user_env()
    systemd_run = shutil.which('systemd-run', path='/usr/bin:/bin')
    if systemd_run and os.getuid() != 0:
        result = subprocess.run([systemd_run, '--user', '--collect', '--quiet', f'--unit={unit}',
                                 '--setenv=PYTHONUNBUFFERED=1', python, script, 'run', path],
                                env=env, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return
    with open(log, 'a') as out:
        subprocess.Popen([python, script, 'run', path], env=env, stdin=subprocess.DEVNULL, stdout=out,
                         stderr=subprocess.STDOUT, start_new_session=True)


def cancel_job(p, port_id):
    job = job_status(p, port_id)
    if not job or job['state'] != 'running':
        return job
    if job.get('pid'):
        try:
            os.killpg(int(job['pid']), signal.SIGTERM)
        except OSError:
            pass
    return job


def finished_unannounced(p):
    """Jobs that ended since the panel last told about them (each is returned once)."""
    out = []
    for path in glob.glob(os.path.join(p['jobs'], '*.json')):
        port_id = os.path.basename(path)[:-5]
        job = job_status(p, port_id)
        if job and job['state'] != 'running' and not job.get('announced'):
            job['announced'] = True
            write(path, json.dumps(job))
            out.append(job)
    return out


class Job:
    """The running side of a job: its progress file, its log and the commands it runs."""

    def __init__(self, path):
        self.path = path
        self.data = read_json(path)
        self.log = open(self.data['log'], 'a', buffering=1)
        self.child = None

    def update(self, **values):
        self.data.update(values)
        write(self.path, json.dumps(self.data))

    def line(self, text):
        self.log.write(text + '\n')

    def stage(self, text):
        self.line(f'==> {text}')
        self.update(stage=text, percent=None)

    def run(self, cmd, cwd=None, env=None, parse=None):
        self.line('$ ' + ' '.join(cmd))
        self.child = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, text=True, errors='replace', bufsize=1)
        last = 0.0
        for raw in self.child.stdout:
            for line in raw.replace('\r', '\n').splitlines():
                if not line:
                    continue
                if parse and parse(self, line):
                    continue
                self.line(line)
                # The last line as the message, written at most twice a second.
                if time.time() - last > 0.5:
                    last = time.time()
                    self.update(message=line[:200])
        code = self.child.wait()
        self.child = None
        if code != 0:
            program = os.path.basename(cmd[0])
            if program.startswith(('python', 'bash')) and len(cmd) > 1:
                program = os.path.basename(cmd[1])
            raise PortsError(f'{program} failed (exit {code}); see the log.')


def fetch_launcher(job, a):
    """Puts the release's launcher in the launcher folder, replacing an older one."""
    rel = job.data.get('release') or {}
    if not rel.get('url'):
        raise PortsError('The newest release has no launcher download.')
    if a.launcher_installed() and a.entry.get('launcher_version') == rel.get('version'):
        return
    job.stage(f'Downloading the launcher {rel.get("tag", "")}')
    cache = os.path.join(a.p['cache'], os.path.basename(rel['url']))
    download(rel['url'], cache, rel.get('sha256'), progress=lambda pct: job.update(percent=pct))
    tmp = tempfile.mkdtemp(prefix='launcher-', dir=a.p['cache'])
    try:
        with tarfile.open(cache) as tar:
            for member in tar.getmembers():
                if member.name.startswith('/') or '..' in member.name.split('/') or \
                        not (member.isfile() or member.isdir()):
                    raise PortsError(f'Unsafe file in the launcher download: {member.name}')
            if hasattr(tarfile, 'data_filter'):
                tar.extractall(tmp, filter='data')
            else:
                tar.extractall(tmp)
        tops = os.listdir(tmp)
        source = os.path.join(tmp, tops[0]) if len(tops) == 1 and os.path.isdir(os.path.join(tmp, tops[0])) else tmp
        dest = a.launcher_dir
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        old = f'{dest}.old-{os.getpid()}'
        if os.path.exists(dest):
            os.rename(dest, old)
        shutil.move(source, dest)
        shutil.rmtree(old, ignore_errors=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
        try:
            os.remove(cache)
        except OSError:
            pass
    record(a.p, a.port['id'], launcher_dir=a.entry.get('launcher_dir'), launcher_version=rel.get('version'))
    a.entry['launcher_version'] = rel.get('version')
    job.line(f'Launcher {rel.get("tag")} in {a.launcher_dir}')


def run_job(path):
    job = Job(path)
    try:
        os.setpgrp()   # cancel_job stops the job and its commands as one group
    except OSError:
        pass           # already a session leader (started without systemd-run)
    job.update(pid=os.getpid())

    def stop(signum, frame):
        if job.child:
            job.child.terminate()
        job.update(state='cancelled', message='Stopped.', finished=time.time())
        sys.exit(1)

    signal.signal(signal.SIGTERM, stop)
    d = job.data
    p = paths(d['home'])
    try:
        port = find_port(d['plugin_dir'], d['id'])
        a = adapter_for(p, port)
        fetch_launcher(job, a)
        a.build(job, d.get('iso'), d.get('bios'))
        record(p, d['id'], installed_release=(d.get('release') or {}).get('version'))
        info = a.detect() or {}
        job.update(state='done', stage='Done', percent=100, message='', finished=time.time(),
                   exe=info.get('exe'), start_dir=info.get('start_dir'), name=a.name)
        job.line('Done.')
    except Exception as e:  # noqa: BLE001 - every failure ends up in the panel
        job.line(f'ERROR: {e}')
        job.update(state='failed', message=str(e), finished=time.time())
        return 1
    finally:
        job.log.close()
    return 0


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'run':
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        sys.exit(run_job(sys.argv[2]))
    print('usage: armadaports.py run JOB.json', file=sys.stderr)
    sys.exit(2)
