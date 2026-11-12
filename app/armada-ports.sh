#!/usr/bin/env bash
# Starts the Armada Ports app. Its Steam shortcut points here.
#
# When you pick Play, the app writes the game to start into ~/.local/share/armada-ports/launch and
# quits; this script then starts the game in its place, so the game has the screen, the
# controller and the memory to itself, and opens the app again on that game's page when the game
# ends. A game that is also in your Steam library starts through ArmadaOS's armada-game-launch
# with its own Steam id, so the Turnip driver and performance profile you set for it in Armada
# Control apply, not the app's.
set -u

here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}/armada-ports"
launch="$data/launch"
log="$data/app.log"
game_launch=/usr/libexec/armada/armada-game-launch

mkdir -p "$data"
# Keep the log of the last few runs only.
if [ -f "$log" ] && [ "$(stat -c %s "$log" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    mv -f "$log" "$log.old"
fi

export ARMADA_PORTS_WRAPPER=1
export ARMADA_PORTS_BACKEND="$here"
args=("$@")
while :; do
    rm -f "$launch"
    echo "== $(date '+%F %T') Armada Ports ${args[*]:-}" >>"$log"
    "$here/armada-ports" "${args[@]}" >>"$log" 2>&1
    status=$?
    [ -f "$launch" ] || exit "$status"
    mapfile -t pick <"$launch"
    rm -f "$launch"
    dir="${pick[0]:-$HOME}"
    exe="${pick[1]:-}"
    port="${pick[2]:-}"
    appid="${pick[3]:-}"
    echo "== $(date '+%F %T') playing $port: $exe (Steam id ${appid:-none})" >>"$log"
    if [ -x "$exe" ]; then
        (
            cd "$dir" 2>/dev/null || cd "$HOME" || exit 1
            if [[ $appid =~ ^[0-9]+$ ]] && [ -x "$game_launch" ]; then
                unset VK_DRIVER_FILES VK_ICD_FILENAMES
                exec env SteamAppId="$appid" "$game_launch" env SteamAppId="${SteamAppId:-}" "$exe"
            fi
            exec "$exe"
        )
    fi
    args=(-- "--focus=$port")
done
