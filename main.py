import asyncio
import json
import os
import time

import decky

import armadaports as core

TICK = 1                 # seconds between looks for requests from the app
ALIVE_EVERY = 5          # seconds between touches of bridge/alive
JOBS_EVERY = 10          # seconds between looks at the jobs
FIRST_CHECK_AFTER = 30   # seconds after loading before the first update check


def _paths():
    return core.paths(decky.DECKY_USER_HOME)


def _plugin_dir():
    return decky.DECKY_PLUGIN_DIR


def _plugin_version():
    with open(os.path.join(decky.DECKY_PLUGIN_DIR, 'package.json')) as f:
        return json.load(f)['version']


async def _run(fn, *args):
    """Runs core work off the event loop and turns problems into a message for the panel."""
    try:
        result = await asyncio.to_thread(fn, *args)
        return {'ok': True, 'result': result}
    except core.PortsError as e:
        return {'ok': False, 'error': str(e)}
    except Exception as e:  # noqa: BLE001 - anything else is logged and reported, never raised into Decky
        decky.logger.exception('Armada Ports call failed')
        return {'ok': False, 'error': f'{type(e).__name__}: {e}'}


class Plugin:
    watcher = None

    async def get_state(self):
        def work():
            result = core.overview(_paths(), _plugin_dir())
            result['current'] = _plugin_version()
            return result
        return await _run(work)

    async def check_updates(self, refresh: bool = True):
        reply = await _run(core.check_updates, _paths(), _plugin_dir(), refresh, _plugin_version())
        if reply['ok']:
            for news in reply['result']['news']:
                await decky.emit('update_available', news)
        return reply

    async def set_steam(self, port: str, appid: int):
        return await _run(core.set_steam, _paths(), port, appid)

    async def app_info(self):
        return await _run(core.app_info, _paths(), _plugin_dir(), _plugin_version())

    async def remember_app(self, appid: int):
        return await _run(core.remember_app, _paths(), appid)

    async def shortcut_for(self, port: str):
        return await _run(core.shortcut_for, _paths(), _plugin_dir(), port)

    async def read_image(self, path: str):
        return await _run(core.read_image, _paths(), path)

    async def bridge_reply(self, req_id: str, reply: dict):
        return await _run(core.bridge_reply, _paths(), req_id, reply)

    async def download_plugin(self):
        """Fetches the newer plugin ZIP; the panel then hands it to Decky's installer."""
        def work():
            p = _paths()
            update = core.load_state(p).get('plugin')
            if not update or not update.get('url'):
                raise core.PortsError('The plugin is up to date.')
            dst = os.path.join(p['cache'], os.path.basename(update['url']))
            core.download(update['url'], dst, update.get('sha256'))
            return {'path': dst, 'version': update['version'], 'sha256': update.get('sha256')}
        return await _run(work)

    async def _watch(self):
        """Answers the app (Steam shortcuts), tells the panel when a job ends, and looks for new
        releases every few hours."""
        start = time.time()
        next_alive = next_jobs = 0.0
        next_check = start + FIRST_CHECK_AFTER
        while True:
            try:
                now = time.time()
                if now >= next_alive:
                    next_alive = now + ALIVE_EVERY
                    await asyncio.to_thread(core.bridge_alive, _paths())
                for req in await asyncio.to_thread(core.bridge_take, _paths(), _plugin_dir()):
                    await decky.emit('bridge_request', req)
                if now >= next_jobs:
                    next_jobs = now + JOBS_EVERY
                    for job in await asyncio.to_thread(core.finished_unannounced, _paths()):
                        await decky.emit('job_finished', job)
                if now >= next_check:
                    next_check = now + core.CHECK_MAX_AGE
                    await self.check_updates(False)
            except Exception:  # noqa: BLE001 - the watcher must keep going
                decky.logger.exception('Armada Ports watcher')
            await asyncio.sleep(TICK)

    async def _main(self):
        decky.logger.info('Armada Ports loaded')
        try:
            where = await asyncio.to_thread(core.install_app, _paths(), _plugin_dir(), _plugin_version())
            decky.logger.info(f'Armada Ports app in {where}')
        except Exception:  # noqa: BLE001 - the plugin still works without the app
            decky.logger.exception('Could not install the Armada Ports app')
        self.watcher = asyncio.get_running_loop().create_task(self._watch())

    async def _unload(self):
        if self.watcher:
            self.watcher.cancel()

    async def _uninstall(self):
        # Installed games stay: they are the player's, and their launchers still work.
        pass
