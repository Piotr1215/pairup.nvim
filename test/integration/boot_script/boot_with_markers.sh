#!/usr/bin/env bash

# Source generic error handling function
source __trap.sh

# Set strict error handling
set -eo pipefail

# Function to display help message
help_function() {
	echo "Usage: __boot.sh [-h|--help]"
	echo ""
	echo "This script automates the boot process based on the current day of the week."
	echo "It sets specific bash options for error handling and executes different commands"
	echo "depending on whether it's a weekday or weekend."
	echo ""
	echo "Options:"
	echo "  -h, --help    Show this help message and exit."
	echo ""
	echo "Features:"
	echo "  - Sources a generic error handling function from __trap.sh."
	echo "  - Sets specific bash options for error handling (set -eo pipefail)."
	echo "  - Moves Alacritty window to HDMI 0."
	echo "  - Launches specific Firefox profiles for work or home, depending on the day."
	echo ""
	echo "Note: This script includes debug options and references to other scripts."
}

# Check for help argument
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
	help_function
	exit 0
fi

weekdays=('Monday' 'Tuesday' 'Wednesday' 'Thursday' 'Friday')

timeoff=0

current_day=$(date +"%A")

echo "$current_day"

# Function to move Alacritty to HDMI 0
move_alacritty_to_hdmi_0() {
	while ! wmctrl -l | grep -q Alacritty; do
		sleep 0.5
	done
	wmctrl -r Alacritty -b remove,maximized_vert,maximized_horz
	wmctrl -r Alacritty -e 0,1920,0,-1,-1
	WID=$(xdotool search --onlyvisible --classname Alacritty | head -1)
	sleep 3
	wmctrl -r Alacritty -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$WID"
	xdotool windowraise "$WID"
}

# Function to modify profiles.ini
update_profiles_ini() {
	profile_to_set=$1
	profiles_ini_path="$HOME/.mozilla/firefox/profiles.ini"

	# Backup current profiles.ini
	cp "$profiles_ini_path" "$profiles_ini_path.bak"

	# Update the profiles.ini
	awk -v profile="$profile_to_set" '
    /^\[Install/ {
        print
        found=1
        next
    }
    found && /^Default=/ {
        sub(/=.*/, "=" profile)
        print
        next
    }
    {
        print
    }' "$profiles_ini_path" >"$profiles_ini_path.tmp" && mv "$profiles_ini_path.tmp" "$profiles_ini_path"

	echo "Updated profiles.ini to use profile: $profile_to_set"
}

if [[ " ${weekdays[*]} " =~ $current_day ]] && [[ "$timeoff" == 0 ]]; then
	/home/decoder/dev/dotfiles/scripts/__create_recurring_tasks.sh
	update_profiles_ini "8gtkyq7h.Work"
	flatpak run com.slack.Slack 2>/dev/null &
	nohup firefox -P "Work" >/dev/null 2>&1 &
	alacritty &
	move_alacritty_to_hdmi_0
else
	# Weekend :)
	update_profiles_ini "g4ip39zz.default-release"
	alacritty &
	move_alacritty_to_hdmi_0
fi

-- CLAUDE:MARKERS:START --
CLAUDE:MARKER-4,1 | Use proper script directory resolution
source "$(dirname "${BASH_SOURCE[0]}")/__trap.sh"
CLAUDE:MARKER-7,1 | Add debug mode option
set -euo pipefail
CLAUDE:MARKER-7,0 | Add configuration variables

# Configuration
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEBUG="${DEBUG:-0}"
CLAUDE:MARKER-10,1 | Improve function documentation with better formatting
show_help() {
CLAUDE:MARKER-37,1 | Make timeoff configurable via environment
readonly TIMEOFF="${TIMEOFF:-0}"
CLAUDE:MARKER-39,1 | Add logging for current day
readonly CURRENT_DAY=$(date +"%A")
CLAUDE:MARKER-41,1 | Add debug logging
[[ "$DEBUG" -eq 1 ]] && echo "[DEBUG] Current day: $CURRENT_DAY"
CLAUDE:MARKER-44,12 | Add error handling and logging to window management
move_alacritty_to_hdmi_0() {
	local max_attempts=20
	local attempt=0

	# Wait for Alacritty window with timeout
	while ! wmctrl -l | grep -q Alacritty; do
		sleep 0.5
		((attempt++))
		if [[ $attempt -ge $max_attempts ]]; then
			echo "[ERROR] Alacritty window not found after ${max_attempts} attempts" >&2
			return 1
		fi
	done

	# Move and maximize window
	wmctrl -r Alacritty -b remove,maximized_vert,maximized_horz
	wmctrl -r Alacritty -e 0,1920,0,-1,-1

	# Get window ID
	local wid
	wid=$(xdotool search --onlyvisible --classname Alacritty | head -1)
	if [[ -z "$wid" ]]; then
		echo "[ERROR] Could not find Alacritty window ID" >&2
		return 1
	fi

	sleep 3
	wmctrl -r Alacritty -b add,maximized_vert,maximized_horz
	xdotool windowactivate --sync "$wid"
	xdotool windowraise "$wid"

	[[ "$DEBUG" -eq 1 ]] && echo "[DEBUG] Alacritty moved to HDMI 0"
}
CLAUDE:MARKER-57,1 | Add validation and error handling - function header
# Function to modify profiles.ini
CLAUDE:MARKER-58,25 | Replace entire function with improved version
update_profiles_ini() {
	local profile_to_set="$1"
	local profiles_ini_path="$HOME/.mozilla/firefox/profiles.ini"

	# Validate input
	if [[ -z "$profile_to_set" ]]; then
		echo "[ERROR] Profile name cannot be empty" >&2
		return 1
	fi

	# Check if profiles.ini exists
	if [[ ! -f "$profiles_ini_path" ]]; then
		echo "[ERROR] Firefox profiles.ini not found at: $profiles_ini_path" >&2
		return 1
	fi

	# Backup current profiles.ini with timestamp
	local backup_path="${profiles_ini_path}.bak.$(date +%Y%m%d_%H%M%S)"
	cp "$profiles_ini_path" "$backup_path"
	[[ "$DEBUG" -eq 1 ]] && echo "[DEBUG] Backed up profiles.ini to: $backup_path"

	# Update the profiles.ini
	awk -v profile="$profile_to_set" '
    /^\[Install/ {
        print
        found=1
        next
    }
    found && /^Default=/ {
        sub(/=.*/, "=" profile)
        print
        next
    }
    {
        print
    }' "$profiles_ini_path" >"$profiles_ini_path.tmp" && mv "$profiles_ini_path.tmp" "$profiles_ini_path"

	echo "[INFO] Updated profiles.ini to use profile: $profile_to_set"
}
CLAUDE:MARKER-83,0 | Add main function for better organization
# Main execution
main() {
CLAUDE:MARKER-84,7 | Improve weekday logic with better readability
	if [[ " ${weekdays[*]} " =~ $CURRENT_DAY ]] && [[ "$TIMEOFF" -eq 0 ]]; then
		[[ "$DEBUG" -eq 1 ]] && echo "[DEBUG] Weekday mode activated"

		# Run work-related tasks
		"${SCRIPT_DIR}/__create_recurring_tasks.sh"
		update_profiles_ini "8gtkyq7h.Work" || echo "[WARN] Failed to update Firefox profile"

		# Launch work applications
		flatpak run com.slack.Slack 2>/dev/null &
		nohup firefox -P "Work" >/dev/null 2>&1 &
		alacritty &

		# Position terminal window
		move_alacritty_to_hdmi_0 || echo "[WARN] Failed to move Alacritty window"
CLAUDE:MARKER-91,5 | Improve weekend mode with logging
	else
		[[ "$DEBUG" -eq 1 ]] && echo "[DEBUG] Weekend mode activated"

		# Update to personal profile
		update_profiles_ini "g4ip39zz.default-release" || echo "[WARN] Failed to update Firefox profile"

		# Launch personal setup
		alacritty &
		move_alacritty_to_hdmi_0 || echo "[WARN] Failed to move Alacritty window"
CLAUDE:MARKER-96,1 | Close the conditional
	fi
CLAUDE:MARKER-97,0 | Close main function and call it
}

# Execute main function
main "$@"
-- CLAUDE:MARKERS:END --