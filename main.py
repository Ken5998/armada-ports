import asyncio
import json
import os
import time

import decky

import armadaports as core

WATCH_EVERY = 10         # seconds between looks at the jobs
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

    async def adopt(self, port: str, folder: str = ''):
        return await _run(core.adopt, _paths(), _plugin_dir(), port, folder)

    async def start_job(self, port: str, action: str, iso: str = '', bios: str = '', add_to_steam: bool = True):
        return await _run(core.start_job, _paths(), _plugin_dir(), port, action, iso, bios, add_to_steam)

    async def cancel_job(self, port: str):
        return await _run(core.cancel_job, _paths(), port)

    async def uninstall(self, port: str):
        return await _run(core.uninstall, _paths(), _plugin_dir(), port)

    async def set_steam(self, port: str, appid: int):
        return await _run(core.set_steam, _paths(), port, appid)

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
        """Tells the panel when a job ends, and looks for new releases every few hours."""
        await asyncio.sleep(FIRST_CHECK_AFTER)
        next_check = 0.0
        while True:
            try:
                for job in await asyncio.to_thread(core.finished_unannounced, _paths()):
                    await decky.emit('job_finished', job)
                if time.time() >= next_check:
                    next_check = time.time() + core.CHECK_MAX_AGE
                    await self.check_updates(False)
            except Exception:  # noqa: BLE001 - the watcher must keep going
                decky.logger.exception('Armada Ports watcher')
            await asyncio.sleep(WATCH_EVERY)

    async def _main(self):
        decky.logger.info('Armada Ports loaded')
        self.watcher = asyncio.get_running_loop().create_task(self._watch())

    async def _unload(self):
        if self.watcher:
            self.watcher.cancel()

    async def _uninstall(self):
        # Installed games stay: they are the player's, and their launchers still work.
        pass
