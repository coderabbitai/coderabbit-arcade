#!/usr/bin/env bash
# Keep the booth game running unattended. The watchdog launches the game, relaunches it whenever it
# exits (a crash, a forced quit, Cmd+Q), and kills and relaunches it when it hangs. The game
# rewrites a heartbeat file every two seconds (app/booth_heartbeat.gd); when the file stops
# changing, the main loop is stuck. Runs on macOS's bash 3.2 and on Linux.
#
# Usage:
#   tools/booth/watchdog.sh [options] -- <game executable> [game arguments]
#
# Example (macOS; tools/booth/macos/setup.sh installs this as a login item):
#   tools/booth/watchdog.sh --log ~/booth-watchdog.log -- \
#     "/Applications/Hoppy’s Adventure Arcade.app/Contents/MacOS/<executable>" -- --booth
#
# Options:
#   --heartbeat <file>   heartbeat file for the game (default: $TMPDIR/hoppy-booth-heartbeat)
#   --hang <seconds>     restart the game when its heartbeat is older than this; 0 turns hang
#                        checks off, for builds without --heartbeat (default: 45)
#   --grace <seconds>    how long a fresh launch has to write its first heartbeat (default: 60)
#   --stop-file <file>   if this file exists when the game exits, stop instead of relaunching
#                        (exit 0); a stop file left from before is removed at startup
#   --log <file>         append the watchdog's events here instead of standard output
#   --backoff <seconds>  first wait before a relaunch; doubles after each short run (default: 2)
#   --max-backoff <s>    longest wait before a relaunch (default: 30)
#   --stable <seconds>   a run at least this long resets the wait to --backoff (default: 60)
#   --term-wait <s>      how long the game gets to exit after SIGTERM before SIGKILL (default: 10)
#   --poll <seconds>     how often to check the game; may be fractional (default: 1)
#
# The game gets --heartbeat=<file> after its other user arguments (a "--" is added if missing).
# SIGTERM, SIGINT or SIGHUP stops the game, then the watchdog, with exit status 0.

heartbeat="${TMPDIR:-/tmp}"
heartbeat="${heartbeat%/}/hoppy-booth-heartbeat"
hang=45
grace=60
stop_file=""
log_file=""
backoff=2
max_backoff=30
stable=60
term_wait=10
poll=1

usage() {
  sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//'
}

die() {
  echo "watchdog: $*" >&2
  exit 2
}

whole_number() {
  case "$2" in
    '' | *[!0-9]*) die "$1 needs a whole number of seconds, not '$2'" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --heartbeat | --hang | --grace | --stop-file | --log | --backoff | --max-backoff | --stable | --term-wait | --poll)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --heartbeat) heartbeat="$2" ;;
        --hang) whole_number "$1" "$2"; hang="$2" ;;
        --grace) whole_number "$1" "$2"; grace="$2" ;;
        --stop-file) stop_file="$2" ;;
        --log) log_file="$2" ;;
        --backoff)
          whole_number "$1" "$2"
          [ "$2" -ge 1 ] || die "--backoff must be at least 1 second"
          backoff="$2"
          ;;
        --max-backoff) whole_number "$1" "$2"; max_backoff="$2" ;;
        --stable) whole_number "$1" "$2"; stable="$2" ;;
        --term-wait) whole_number "$1" "$2"; term_wait="$2" ;;
        --poll)
          case "$2" in
            '' | *[!0-9.]* | *.*.* | .) die "--poll needs a number of seconds, not '$2'" ;;
          esac
          awk -v p="$2" 'BEGIN { exit !(p > 0) }' || die "--poll must be more than 0 seconds"
          poll="$2"
          ;;
      esac
      shift 2
      ;;
    -h | --help) usage; exit 0 ;;
    --) shift; break ;;
    *) die "unknown option '$1' (the game command goes after --)" ;;
  esac
done
[ $# -gt 0 ] || die "no game command; pass it after --"
[ "$max_backoff" -ge "$backoff" ] || max_backoff="$backoff"

game=("$@")
if [ "$hang" -gt 0 ]; then
  separator=0
  for arg in "$@"; do
    [ "$arg" = "--" ] && separator=1
  done
  [ "$separator" -eq 1 ] || game+=("--")
  game+=("--heartbeat=$heartbeat")
fi

say() {
  local line
  line="$(date '+%Y-%m-%dT%H:%M:%S') watchdog: $*"
  if [ -n "$log_file" ]; then
    echo "$line" >> "$log_file"
  else
    echo "$line"
  fi
}

child=""

# SIGTERM, then SIGKILL if the game is still there after --term-wait seconds. The caller reaps it.
terminate() {
  local waited=0
  kill -TERM "$1" 2>/dev/null
  while kill -0 "$1" 2>/dev/null && [ "$waited" -lt "$term_wait" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$1" 2>/dev/null; then
    say "the game (pid $1) ignored SIGTERM for $term_wait s; sending SIGKILL"
    kill -KILL "$1" 2>/dev/null
  fi
}

stop() {
  trap - TERM INT HUP
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
    say "stopping the game (pid $child)"
    terminate "$child"
    wait "$child" 2>/dev/null
  fi
  say "stopped"
  exit 0
}
trap stop TERM INT HUP

# Sleep in one-second steps, so a stop signal is handled within a second.
pause() {
  local slept=0
  while [ "$slept" -lt "$1" ]; do
    sleep 1
    slept=$((slept + 1))
  done
}

[ -z "$log_file" ] || mkdir -p "$(dirname "$log_file")" || die "cannot create the folder for $log_file"
if [ "$hang" -gt 0 ]; then
  mkdir -p "$(dirname "$heartbeat")" || die "cannot create the folder for $heartbeat"
fi
if [ -n "$stop_file" ] && [ -e "$stop_file" ]; then
  rm -f "$stop_file"
  say "removed the stop file left from before ($stop_file)"
fi
if [ "$hang" -gt 0 ]; then
  say "watching ${game[*]} (restart after $hang s without a heartbeat)"
else
  say "watching ${game[*]} (hang checks off)"
fi

wait_before_relaunch="$backoff"
while :; do
  rm -f "$heartbeat"
  "${game[@]}" &
  child=$!
  launched=$(date +%s)
  say "launched the game (pid $child)"
  while kill -0 "$child" 2>/dev/null; do
    sleep "$poll"
    [ "$hang" -gt 0 ] || continue
    now=$(date +%s)
    [ $((now - launched)) -ge "$grace" ] || continue
    beat=$(cat "$heartbeat" 2>/dev/null)
    case "$beat" in
      '' | *[!0-9]*) last="$launched" ;;
      *) last="$beat" ;;
    esac
    if [ $((now - last)) -gt "$hang" ]; then
      say "the game has not written a heartbeat for $((now - last)) s; restarting it"
      terminate "$child"
      break
    fi
  done
  wait "$child" 2>/dev/null
  status=$?
  child=""
  ran=$(($(date +%s) - launched))
  if [ "$status" -gt 128 ]; then
    say "the game exited after $ran s (signal $((status - 128)))"
  else
    say "the game exited after $ran s (status $status)"
  fi
  if [ -n "$stop_file" ] && [ -e "$stop_file" ]; then
    say "stop file $stop_file is present; not relaunching"
    exit 0
  fi
  [ "$ran" -lt "$stable" ] || wait_before_relaunch="$backoff"
  say "relaunching in $wait_before_relaunch s"
  pause "$wait_before_relaunch"
  wait_before_relaunch=$((wait_before_relaunch * 2))
  [ "$wait_before_relaunch" -le "$max_backoff" ] || wait_before_relaunch="$max_backoff"
done
