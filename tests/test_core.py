import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'py_modules'))
import armadaports as core  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..')


def make_payload(path, files):
    with zipfile.ZipFile(path, 'w') as z:
        for name, data in files.items():
            z.writestr(name, data)


def pinyon_files(version='0.7.1', extra=None):
    files = {
        'config/release.json': json.dumps({'version': version}),
        'tools/pinyon.py': 'print("hi")\n',
    }
    files.update(extra or {})
    return files


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.p = core.paths(self.home)

    def tearDown(self):
        self.tmp.cleanup()


class VersionTest(unittest.TestCase):
    def test_order(self):
        self.assertGreater(core.version_key('v0.10.0'), core.version_key('0.9.9'))
        self.assertGreater(core.version_key('0.3.0'), core.version_key('0.3.0-rc.1'))
        self.assertEqual(core.version_key('v1.2'), core.version_key('1.2.0'))

    def test_shortcut_id_matches_launchers(self):
        # zlib.crc32('"' + exe + '"' + name) | 0x80000000, as scripts/add-to-steam.py computes it.
        exe = '/home/a/.local/share/FifaStreet-arm64/game/fifastreet.sh'
        import zlib
        self.assertEqual(core.shortcut_app_id(exe, 'FIFA Street'),
                         zlib.crc32(f'"{exe}"FIFA Street'.encode()) | 0x80000000)


class ReleaseTest(unittest.TestCase):
    def test_sysroot_builds_are_not_releases(self):
        rels = [{'tag_name': 'sysroot-2026.11.09.2'}, {'tag_name': 'v0.2.0'}, {'tag_name': 'v0.1.12'},
                {'tag_name': 'v0.3.0', 'prerelease': True}, {'tag_name': 'v0.4.0', 'draft': True}]
        self.assertEqual(core.pick_release(rels, None)['tag_name'], 'v0.2.0')
        self.assertIsNone(core.pick_release([{'tag_name': 'sysroot-1'}], None))


class CatalogTest(unittest.TestCase):
    def test_catalog_is_valid(self):
        ports = core.load_catalog(ROOT)
        ids = [p['id'] for p in ports]
        self.assertEqual(len(ids), len(set(ids)))
        for port in ports:
            self.assertRegex(port['repo'], r'^Ken5998/[a-z0-9-]+$')
            self.assertIn(port.get('adapter'), (None, *core.ADAPTERS))
            if port.get('adapter'):
                self.assertTrue(port.get('launcher'), port['id'])
            if port.get('adapter') in ('overlay', 'rusty-mcla'):
                for key in ('data', 'script', 'game', 'files'):
                    self.assertIn(key, port['overlay'], port['id'])


class PayloadTest(Base):
    def test_extract_then_update(self):
        payload = os.path.join(self.home, 'p.zip')
        dest = os.path.join(self.home, 'src')
        make_payload(payload, pinyon_files(extra={'a.txt': 'one', 'gone.txt': 'x'}))
        self.assertEqual(core.extract_pinyon_payload(payload, dest), 4)
        marker = open(os.path.join(dest, '.pinyon-source-sha256')).read().strip()
        self.assertEqual(marker, hashlib.sha256(open(payload, 'rb').read()).hexdigest().upper())
        self.assertIn('gone.txt', open(os.path.join(dest, '.pinyon-source-files')).read())
        # The same payload again changes nothing.
        self.assertEqual(core.extract_pinyon_payload(payload, dest), 0)
        # A new payload: a.txt changes, gone.txt goes, untouched files keep their time, .local stays.
        os.makedirs(os.path.join(dest, '.local'))
        open(os.path.join(dest, '.local', 'save'), 'w').write('keep')
        old = time.time() - 1000
        os.utime(os.path.join(dest, 'tools/pinyon.py'), (old, old))
        make_payload(payload, pinyon_files(extra={'a.txt': 'two'}))
        self.assertEqual(core.extract_pinyon_payload(payload, dest), 1)
        self.assertEqual(open(os.path.join(dest, 'a.txt')).read(), 'two')
        self.assertFalse(os.path.exists(os.path.join(dest, 'gone.txt')))
        self.assertTrue(os.path.exists(os.path.join(dest, '.local', 'save')))
        self.assertAlmostEqual(os.path.getmtime(os.path.join(dest, 'tools/pinyon.py')), old, delta=1)

    def test_refuses_escape(self):
        payload = os.path.join(self.home, 'p.zip')
        make_payload(payload, {'../evil': 'x'})
        with self.assertRaises(core.PortsError):
            core.extract_pinyon_payload(payload, os.path.join(self.home, 'src'))

    def test_source_folder(self):
        p = core.paths(self.home)
        a = core.adapter_for(p, core.find_port(ROOT, 'pinyon-shift'))
        base = os.path.join(p['share'], 'PinyonShift', 'source')
        self.assertEqual(a.source_folder(), os.path.join(base, '0.1.1'))
        payload = os.path.join(self.home, 'p.zip')
        make_payload(payload, pinyon_files())
        core.extract_pinyon_payload(payload, os.path.join(base, '0.2.0'))
        self.assertEqual(a.source_folder(), os.path.join(base, '0.2.0'))


class DetectTest(Base):
    def port(self, port_id):
        return core.find_port(ROOT, port_id)

    def test_pinyon(self):
        a = core.adapter_for(self.p, self.port('pinyon-shift'))
        self.assertIsNone(a.detect())
        src = os.path.join(self.p['share'], 'PinyonShift', 'source', '0.1.1')
        payload = os.path.join(self.home, 'p.zip')
        make_payload(payload, pinyon_files('0.7.0'))
        core.extract_pinyon_payload(payload, src)
        info = a.detect()
        self.assertEqual(info['version'], '0.7.0')
        self.assertFalse(info['built'])
        self.assertTrue(a.update_available(info, {'version': '0.7.1'}))
        self.assertFalse(a.update_available(info, {'version': '0.7.0'}))

    def test_pinyon_custom_root(self):
        root = os.path.join(self.home, 'games', 'PS')
        os.makedirs(os.path.join(self.p['share'], 'PinyonShift'))
        open(os.path.join(self.p['share'], 'PinyonShift', 'install-root.txt'), 'w').write(root + '\n')
        payload = os.path.join(self.home, 'p.zip')
        make_payload(payload, pinyon_files())
        core.extract_pinyon_payload(payload, os.path.join(root, 'source', '0.1.1'))
        a = core.adapter_for(self.p, self.port('pinyon-shift'))
        self.assertEqual(a.detect()['data'], os.path.join(root, 'source', '0.1.1'))
        self.assertEqual(a.remove(), [os.path.join(root, 'source', '0.1.1')])

    def test_fifa(self):
        a = core.adapter_for(self.p, self.port('fifa-street'))
        self.assertIsNone(a.detect())
        overlay = os.path.join(self.p['share'], 'FifaStreet-arm64', 'overlay')
        os.makedirs(overlay)
        env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t',
                   GIT_COMMITTER_EMAIL='t@t')
        subprocess.run(['git', 'init', '-q', overlay], check=True)
        subprocess.run(['git', '-C', overlay, 'commit', '-q', '--allow-empty', '-m', 'x'], check=True, env=env)
        info = a.detect()
        self.assertEqual(len(info['commit']), 40)
        self.assertFalse(info['built'])
        self.assertTrue(a.update_available(info, {'version': '0.2.0', 'commit': '0' * 40}))
        self.assertFalse(a.update_available(dict(info, version='0.2.0'), {'version': '0.2.0', 'commit': info['commit']}))

    def test_saints(self):
        a = core.adapter_for(self.p, self.port('saints-reborn'))
        self.assertIsNone(a.detect())
        dist = os.path.join(self.p['share'], 'SaintsReborn-arm64', 'SaintsReborn', 'dist')
        os.makedirs(os.path.join(dist, 'game'))
        open(os.path.join(dist, 'saintsrow'), 'w').close()
        open(os.path.join(dist, 'game', 'default.xex'), 'w').close()
        info = a.detect()
        self.assertTrue(info['built'] and info['game_files'])
        self.assertEqual(info['start_dir'], dist)
        self.assertEqual(a.name, 'Saints Reborn')
        self.assertEqual(a.env()['SR_ADD_TO_STEAM'], '0')

    def test_rusty_mcla(self):
        a = core.adapter_for(self.p, self.port('rusty-mcla'))
        data = os.path.join(self.p['share'], 'RustyMCLA-arm64')
        os.makedirs(os.path.join(data, 'game'))
        os.makedirs(os.path.join(data, 'build'))
        open(os.path.join(data, 'game', 'mcla.sh'), 'w').close()
        open(os.path.join(data, 'build', 'release'), 'w').write('v0.3.1\n')
        open(os.path.join(data, 'launcher.conf'), 'w').write(
            'disc=/x.iso\nresolution=1600x900\nfill=1\nfps_cap=30\nrender_scale=67\nadd_to_steam=1\n')
        info = a.detect()
        self.assertEqual(info['version'], '0.3.1')
        self.assertFalse(info['game_files'])
        self.assertTrue(a.update_available(info, {'version': '0.4.0'}))
        self.assertFalse(a.update_available(info, {'version': '0.3.1', 'commit': 'f' * 40}))
        env = a.env()
        self.assertEqual((env['MCLA_RESOLUTION'], env['MCLA_WINDOW_MODE'], env['MCLA_FPS_CAP'],
                          env['MCLA_RENDER_SCALE'], env['MCLA_ADD_TO_STEAM']),
                         ('1600x900', 'borderless', '30', '0.67', '0'))
        self.assertEqual(a.name, 'Midnight Club: Los Angeles')

    def test_mm3(self):
        a = core.adapter_for(self.p, self.port('mm3-recomp'))
        self.assertIsNone(a.detect())
        data = os.path.join(self.p['share'], 'MidtownMadness3')
        os.makedirs(os.path.join(data, 'bin'))
        os.makedirs(os.path.join(data, 'game_files'))
        open(os.path.join(data, 'bin', 'mm3_recomp'), 'w').close()
        json.dump({'version': '0.1.12', 'built': 1}, open(os.path.join(data, 'installed.json'), 'w'))
        info = a.detect()
        self.assertEqual(info['version'], '0.1.12')
        self.assertFalse(info['game_files'])
        self.assertTrue(a.update_available(info, {'version': '0.2.0'}))
        self.assertTrue(info['exe'].endswith('midtown-madness-3.sh'))

    def test_adopt_needs_an_install(self):
        with self.assertRaises(core.PortsError):
            core.adopt(self.p, ROOT, 'pinyon-shift')
        folder = os.path.join(self.home, 'Desktop', 'PinyonShift')
        os.makedirs(folder)
        open(os.path.join(folder, 'PinyonShiftLauncher'), 'w').close()
        payload = os.path.join(self.home, 'p.zip')
        make_payload(payload, pinyon_files())
        core.extract_pinyon_payload(payload, os.path.join(self.p['share'], 'PinyonShift', 'source', '0.1.1'))
        view = core.adopt(self.p, ROOT, 'pinyon-shift', folder)
        self.assertEqual(view['launcher_dir'], folder)
        self.assertEqual(view['installed']['version'], '0.7.1')
        self.assertIsNotNone(view['legacy_appid'])

    def test_unsupported_port_view(self):
        view = core.overview(self.p, ROOT)
        reskate = next(v for v in view['ports'] if v['id'] == 'reskate')
        self.assertFalse(reskate['supported'])
        self.assertIsNone(reskate['installed'])


class EventTest(unittest.TestCase):
    class Sink:
        def __init__(self):
            self.data, self.lines = {}, []

        def update(self, **v):
            self.data.update(v)

        def line(self, text):
            self.lines.append(text)

    def test_mm3_events(self):
        job = self.Sink()
        self.assertTrue(core.mm3_event(job, '@step\t3\t5\tTranslating'))
        self.assertEqual(job.data['stage'], '3/5 Translating')
        core.mm3_event(job, '@progress\t0.25\tfile.c')
        self.assertEqual((job.data['percent'], job.data['message']), (25.0, 'file.c'))
        core.mm3_event(job, '@progress\t-1\tCompiling')
        self.assertIsNone(job.data['percent'])
        self.assertFalse(core.mm3_event(job, 'plain line'))

    def test_steps(self):
        job = self.Sink()
        core.step_event(job, '==> Getting the game')
        self.assertEqual(job.data['stage'], 'Getting the game')
        core.step_event(job, '==> [10:00:00] Toolchain')
        self.assertEqual(job.data['stage'], 'Toolchain')
        core.step_event(job, '[5/10] cc x.c')
        self.assertEqual(job.data['percent'], 50)


class FakeAdapter(core.Adapter):
    supported = True

    def detect(self):
        done = os.path.join(self.p['share'], 'fake', 'done')
        return {'version': '1.0.0', 'built': os.path.exists(done), 'exe': done, 'start_dir': os.path.dirname(done)}

    def build(self, job, iso, bios):
        job.stage('Building')
        os.makedirs(os.path.join(self.p['share'], 'fake'), exist_ok=True)
        script = 'echo "==> [10:00:00] Compiling"; echo "[1/4] a.c"; echo "[2/4] b.c"; ' + \
                 ('exit 3' if iso == 'fail' else f'touch "{self.p["share"]}/fake/done"')
        job.run(['sh', '-c', script], parse=core.step_event)


class JobTest(Base):
    def setUp(self):
        super().setUp()
        self.plugin = os.path.join(self.home, 'plugin')
        os.makedirs(self.plugin)
        # A launcher release as a local tarball.
        tar_path = os.path.join(self.home, 'Fake-Launcher.tar.gz')
        with tarfile.open(tar_path, 'w:gz') as tar:
            data = b'#!/bin/sh\necho 1.0.0\n'
            info = tarfile.TarInfo('Fake/fake-launcher')
            info.size, info.mode = len(data), 0o755
            tar.addfile(info, io.BytesIO(data))
        self.release = {'tag': 'v1.0.0', 'version': '1.0.0', 'url': 'file://' + tar_path,
                        'sha256': hashlib.sha256(open(tar_path, 'rb').read()).hexdigest()}
        json.dump({'ports': [{'id': 'fake', 'name': 'Fake', 'repo': 'Ken5998/fake', 'adapter': 'fake',
                              'launcher': 'fake-launcher', 'needs': ['iso']}]},
                  open(os.path.join(self.plugin, 'ports.json'), 'w'))
        core.ADAPTERS['fake'] = FakeAdapter
        state = core.load_state(self.p)
        state['latest']['fake'] = self.release
        core.save_state(self.p, state)

    def tearDown(self):
        core.ADAPTERS.pop('fake', None)
        super().tearDown()

    def run_inline(self, iso):
        job = {'id': 'fake', 'action': 'install', 'state': 'running', 'log': os.path.join(self.home, 'log'),
               'started': time.time(), 'home': self.home, 'plugin_dir': self.plugin, 'release': self.release,
               'iso': iso}
        path = core.job_file(self.p, 'fake')
        core.write(path, json.dumps(job))
        code = core.run_job(path)
        return code, core.job_status(self.p, 'fake')

    def test_install_succeeds(self):
        code, job = self.run_inline('disc.iso')
        self.assertEqual(code, 0, open(os.path.join(self.home, 'log')).read())
        self.assertEqual(job['state'], 'done')
        self.assertTrue(job['exe'].endswith('done'))
        launcher = os.path.join(self.p['launchers'], 'fake', 'fake-launcher')
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertEqual(core.load_state(self.p)['ports']['fake']['launcher_version'], '1.0.0')
        log = open(os.path.join(self.home, 'log')).read()
        self.assertIn('[2/4] b.c', log)
        self.assertEqual([j['id'] for j in core.finished_unannounced(self.p)], ['fake'])
        self.assertEqual(core.finished_unannounced(self.p), [])

    def test_failure_is_reported(self):
        code, job = self.run_inline('fail')
        self.assertEqual(code, 1)
        self.assertEqual(job['state'], 'failed')
        self.assertIn('exit 3', job['message'])
        self.assertEqual(job['stage'], 'Compiling')
        self.assertEqual(job['percent'], 50)

    def test_dead_job_is_failed(self):
        core.write(core.job_file(self.p, 'fake'), json.dumps({'state': 'running', 'pid': 2 ** 22 + 7,
                                                               'started': time.time()}))
        self.assertEqual(core.job_status(self.p, 'fake')['state'], 'failed')

    def test_bad_checksum_changes_nothing(self):
        self.release['sha256'] = '0' * 64
        code, job = self.run_inline('disc.iso')
        self.assertEqual(job['state'], 'failed')
        self.assertIn('checksum', job['message'])
        self.assertFalse(os.path.exists(os.path.join(self.p['launchers'], 'fake')))

    def test_spawned_job_runs_on_its_own(self):
        # The real path: a separate process (systemd-run when there is a user session).
        job = core.start_job(self.p, self.plugin, 'fake', 'install', iso=__file__)
        self.assertEqual(job['state'], 'running')
        # The child imports the module from its file; the fake adapter is not there, so it fails
        # cleanly with the error in the job file.
        for _ in range(100):
            status = core.job_status(self.p, 'fake')
            if status['state'] != 'running':
                break
            time.sleep(0.1)
        self.assertEqual(status['state'], 'failed')
        self.assertIn('install', status['message'])


if __name__ == '__main__':
    unittest.main()
