#!/usr/bin/env bash
# Set up a Mac to run Hoppy's Adventure Arcade as an unattended booth kiosk, and put it back after
# the show. Staff steps are in docs/booth-runbook.md.
#
# Usage:
#   tools/booth/macos/setup.sh --app "/Applications/Hoppy’s Adventure Arcade.app" [--route <name>]
#       Print the plan. Nothing changes.
#   tools/booth/macos/setup.sh --app "/Applications/Hoppy’s Adventure Arcade.app" [--route <name>] --apply
#       Make the changes. Asks for an administrator password for the system settings.
#   tools/booth/macos/setup.sh --undo [--apply]
#       Print (or, with --apply, make) the changes that put the Mac back: the settings recorded
#       before setup are restored exactly. Without that record it changes no system setting and
#       lists what to restore by hand.
#
# --apply does this:
#   - copies tools/booth/watchdog.sh to ~/Library/Application Support/HoppyBooth/, and records the
#     settings below as they were, for --undo (only the first time)
#   - installs a LaunchAgent that starts the watchdog, and through it the game in booth mode, at
#     login, and restarts the watchdog if it dies; it starts the game right away
#   - removes the download quarantine from the app, so Gatekeeper doesn't block it
#   - turns off system sleep, display sleep, disk sleep and Power Nap, and restarts after a power cut
#   - turns off the screen saver, automatic macOS and App Store updates, and crash report dialogs
# Settings macOS doesn't let a script change are listed at the end (automatic login, notifications,
# display, volume, controllers).

label="ai.coderabbit.arcade.booth"
support="$HOME/Library/Application Support/HoppyBooth"
logs="$HOME/Library/Logs/HoppyBooth"
agent="$HOME/Library/LaunchAgents/$label.plist"
snapshot="$support/settings-before.tsv"
# The preferences the setup changes: scope, domain, key, type, booth value. "host" is the
# -currentHost domain; "system" is machine-wide and needs sudo to write.
SETTINGS=(
  "host com.apple.screensaver idleTime int 0"
  "system /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled bool false"
  "system /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload bool false"
  "system /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates bool false"
  "system /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall bool false"
  "system /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall bool false"
  "system /Library/Preferences/com.apple.commerce AutoUpdate bool false"
  "user com.apple.CrashReporter DialogType string none"
)
# The power settings the setup changes.
PMSET_KEYS="sleep displaysleep disksleep powernap autorestart"
here="$(cd "$(dirname "$0")" && pwd)"
app=""
route=""
apply=0
undo=0

usage() {
  sed -n '2,/^$/p' "$0" | sed -e 's/^# \{0,1\}//'
}

die() {
  echo "setup: $*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app | --route)
      [ $# -ge 2 ] || die "$1 needs a value"
      if [ "$1" = "--app" ]; then app="${2%/}"; else route="$2"; fi
      shift 2
      ;;
    --apply) apply=1; shift ;;
    --undo) undo=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option '$1'" ;;
  esac
done

if [ "$apply" -eq 1 ] && [ "$(uname -s)" != "Darwin" ]; then
  die "--apply only runs on macOS"
fi
# launchd doesn't run from this folder, so the agent needs an absolute path to the app.
case "$app" in
  "" | /*) ;;
  *) app="$PWD/$app" ;;
esac

# Print each command; run it only with --apply. A failed command is reported and the rest go on.
failures=0
run() {
  local line="  \$" arg
  for arg in "$@"; do
    case "$arg" in
      *[[:space:]\'\"\&]*) line="$line \"$arg\"" ;;
      *) line="$line $arg" ;;
    esac
  done
  echo "$line"
  [ "$apply" -eq 1 ] || return 0
  if ! "$@"; then
    echo "    ^ failed; the remaining steps continue" >&2
    failures=$((failures + 1))
  fi
}

step() {
  echo
  echo "$*"
}

xml() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# The `defaults` command line that reads (r) or writes (w) a setting in this scope.
reader() {
  if [ "$1" = host ]; then r=(defaults -currentHost); else r=(defaults); fi
}
writer() {
  case "$1" in
    host) w=(defaults -currentHost) ;;
    system) w=(sudo defaults) ;;
    *) w=(defaults) ;;
  esac
}

# Write each setting as it is now to the record, once: re-running the setup keeps the first one.
record_settings() {
  local entry scope domain key type value read_type
  if [ -e "$snapshot" ]; then
    echo "  kept the record from the first setup"
    return 0
  fi
  {
    for entry in "${SETTINGS[@]}"; do
      read -r scope domain key type value <<<"$entry"
      reader "$scope"
      if value=$("${r[@]}" read "$domain" "$key" 2>/dev/null); then
        read_type=$("${r[@]}" read-type "$domain" "$key" 2>/dev/null)
        case "$read_type" in
          *boolean) type=bool ;;
          *integer) type=int ;;
          *float) type=float ;;
          *string) type=string ;;
          *) type=unsupported ;;
        esac
      else
        type=absent
        value=""
      fi
      printf 'defaults\t%s\t%s\t%s\t%s\t%s\n' "$scope" "$domain" "$key" "$type" "$value"
    done
    for key in $PMSET_KEYS; do
      value=$(pmset -g | awk -v k="$key" '$1 == k { print $2; exit }')
      [ -z "$value" ] || printf 'pmset\t%s\t%s\n' "$key" "$value"
    done
  } > "$snapshot" || die "cannot write the settings record $snapshot"
  echo "  recorded in $snapshot"
}

# The app's executable, from its Info.plist.
executable() {
  local plist="$1/Contents/Info.plist" name=""
  [ -f "$plist" ] || return 0
  if [ -x /usr/libexec/PlistBuddy ]; then
    name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null)"
  else
    name="$(sed -n '/<key>CFBundleExecutable<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$plist")"
  fi
  [ -n "$name" ] && printf '%s' "$1/Contents/MacOS/$name"
}

if [ "$apply" -eq 1 ]; then
  echo "Applying. Commands run as they are listed."
else
  echo "Plan only: nothing will change. Run again with --apply to make these changes."
fi

if [ "$undo" -eq 1 ]; then
  if [ "$apply" -eq 1 ] && [ -f "$snapshot" ]; then
    sudo -v || die "the system settings need an administrator password"
  fi
  step "Stop the booth game and remove its login item:"
  run launchctl bootout "gui/$(id -u)/$label"
  run rm -f "$agent"
  unrecorded=0
  if [ -f "$snapshot" ]; then
    step "Put back the settings recorded before setup ($snapshot):"
    while IFS=$'\t' read -r kind a b c d e <&3; do
      case "$kind" in
        defaults)
          writer "$a"
          reader "$a"
          case "$d" in
            absent)
              # Only delete what setup added; a key already gone needs nothing.
              if [ "$apply" -eq 0 ] || "${r[@]}" read "$b" "$c" >/dev/null 2>&1; then
                run "${w[@]}" delete "$b" "$c"
              fi
              ;;
            bool)
              case "$e" in 1 | [Tt]rue | YES | [Yy]es) e=true ;; *) e=false ;; esac
              run "${w[@]}" write "$b" "$c" -bool "$e"
              ;;
            int | float | string) run "${w[@]}" write "$b" "$c" "-$d" "$e" ;;
            *)
              echo "  restore $b $c by hand: it held a value this script can't rewrite"
              unrecorded=1
              ;;
          esac
          ;;
        pmset) run sudo pmset -a "$a" "$b" ;;
      esac
    done 3< "$snapshot"
    [ "$failures" -gt 0 ] || run rm -f "$snapshot"
  else
    unrecorded=1
    step "No record of this Mac's settings before setup ($snapshot), so none are changed."
    cat <<'BY_HAND'
  Restore them by hand if the setup changed them:
  - System Settings > Lock Screen: the display and sleep times you want.
  - System Settings > Energy (or Battery): Power Nap and starting up after a power failure.
  - System Settings > Screen Saver: the screen saver and when it starts.
  - System Settings > General > Software Update > Automatic Updates: switch each one back on.
  - In Terminal, to get crash dialogs back: defaults delete com.apple.CrashReporter DialogType
BY_HAND
  fi
  step "Left in place: the logs in $logs and the session logs under the game's user data."
  echo "Turn automatic login and Do Not Disturb back off by hand if you turned them on."
  if [ "$apply" -eq 1 ] && { [ "$failures" -gt 0 ] || [ "$unrecorded" -eq 1 ]; }; then
    echo
    [ "$failures" -eq 0 ] || echo "$failures step(s) failed; see the messages above."
    [ "$unrecorded" -eq 0 ] || echo "Some settings need restoring by hand; see above."
    exit 1
  fi
  exit 0
fi

[ -n "$app" ] || die "--app is required: the path to Hoppy’s Adventure Arcade.app"
binary="$(executable "$app")"
if [ -z "$binary" ]; then
  [ "$apply" -eq 0 ] || die "cannot read the app's executable from $app/Contents/Info.plist"
  binary="$app/Contents/MacOS/<executable>"
  echo "(Can't read $app here; the plan shows a placeholder for its executable.)"
fi
[ "$apply" -eq 0 ] || [ -x "$binary" ] || die "$binary is missing or not executable"

game_args=(-- --booth)
[ -z "$route" ] || game_args+=("--route=$route")
watchdog=("/bin/bash" "$support/watchdog.sh" --log "$logs/watchdog.log" --heartbeat "$support/heartbeat"
  --stop-file "$support/stop" -- "$binary" "${game_args[@]}")
plist_arguments=""
for arg in "${watchdog[@]}"; do
  plist_arguments="$plist_arguments
		<string>$(xml "$arg")</string>"
done
plist="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProgramArguments</key>
	<array>$plist_arguments
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardOutPath</key>
	<string>$(xml "$logs/game.log")</string>
	<key>StandardErrorPath</key>
	<string>$(xml "$logs/game.log")</string>
</dict>
</plist>"

if [ "$apply" -eq 1 ]; then
  sudo -v || die "the system settings need an administrator password"
fi

step "Install the watchdog:"
run mkdir -p "$support" "$logs"
run cp "$here/../watchdog.sh" "$support/watchdog.sh"
run chmod 755 "$support/watchdog.sh"

step "Record the current settings, so --undo can put them back ($snapshot):"
if [ "$apply" -eq 1 ]; then
  record_settings
else
  echo "  would record the preferences and power settings changed below, unless a record exists"
fi

step "Let Gatekeeper open the app (it is ad-hoc signed, not notarized):"
run xattr -dr com.apple.quarantine "$app"

step "Keep the Mac awake, and start again after a power cut:"
run sudo pmset -a sleep 0 displaysleep 0 disksleep 0 powernap 0
run sudo pmset -a autorestart 1

step "No screen saver, no automatic updates, no crash dialogs over the game:"
for entry in "${SETTINGS[@]}"; do
  read -r scope domain key type value <<<"$entry"
  writer "$scope"
  run "${w[@]}" write "$domain" "$key" "-$type" "$value"
done

step "Start the game at login and keep it running ($agent):"
if [ "$apply" -eq 1 ]; then
  if ! { mkdir -p "$(dirname "$agent")" && printf '%s\n' "$plist" > "$agent"; }; then
    die "cannot write $agent"
  fi
  echo "  wrote $agent"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
else
  echo "  would write:"
  printf '%s\n' "$plist" | sed 's/^/    /'
fi
run launchctl bootstrap "gui/$(id -u)" "$agent"

step "Do these by hand (macOS offers no reliable command for them):"
cat <<'MANUAL'
  1. System Settings > Users & Groups > Automatically log in as: the booth account.
     (FileVault must be off for automatic login.)
  2. Control Center > Focus: click Do Not Disturb so it stays on. Then in System Settings >
     Notifications, turn off "Allow notifications when mirroring or sharing the display".
  3. System Settings > Displays: the booth resolution, and mirror or extend as the booth needs.
  4. Set the volume for the floor, and pair or plug in the controllers.
  5. Restart the Mac and check that the game starts on its own within a minute.
MANUAL

if [ "$apply" -eq 1 ]; then
  echo
  if [ "$failures" -gt 0 ]; then
    echo "$failures step(s) failed; see the messages above."
    exit 1
  fi
  echo "Done. The watchdog's log is $logs/watchdog.log."
fi
