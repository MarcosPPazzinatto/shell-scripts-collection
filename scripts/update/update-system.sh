#!/usr/bin/env bash
# update-system.sh
# Script to update and upgrade Linux-based systems.
# Supports: apt, dnf, yum, pacman, zypper, apk (+ optional snap/flatpak).
# Options:
#   --check-only          : show pending updates without applying
#   --dist-upgrade        : use dist-upgrade/full-upgrade where applicable
#   --include-snaps       : also update snap packages if snap is present
#   --include-flatpak     : also update flatpak apps/runtimes if flatpak is present
#   --autoremove          : remove unused packages after upgrade (if supported)
#   --reboot-if-needed    : reboot automatically if the system requires it
#   -y|--yes              : non-interactive (assume "yes")
#   -h|--help             : show help
#
# Exit codes:
#   0 success, 1 usage error, 2 unsupported distro/PM, 3 update failure

set -euo pipefail

YES_FLAG=""
CHECK_ONLY=false
DIST_UPGRADE=false
DO_AUTOREMOVE=false
DO_REBOOT=false
DO_SNAP=false
DO_FLATPAK=false

log()  { printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }
err()  { printf "[%s] ERROR: %s\n" "$(date '+%F %T')" "$*" >&2; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

usage() {
  sed -n '1,100p' "$0" | sed -n '1,40p' | sed 's/^# \{0,1\}//'
}

# --- Parse args --------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)       CHECK_ONLY=true ;;
    --dist-upgrade)     DIST_UPGRADE=true ;;
    --autoremove)       DO_AUTOREMOVE=true ;;
    --reboot-if-needed) DO_REBOOT=true ;;
    --include-snaps)    DO_SNAP=true ;;
    --include-flatpak)  DO_FLATPAK=true ;;
    -y|--yes)           YES_FLAG="-y" ;;
    -h|--help)          usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# --- Require root for actions (not needed for check-only) --------------------
if ! $CHECK_ONLY; then
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (use sudo)."
    exit 1
  fi
fi

# --- Detect package manager --------------------------------------------------
PM=""
if   cmd_exists apt-get;  then PM="apt"
elif cmd_exists dnf;      then PM="dnf"
elif cmd_exists yum;      then PM="yum"
elif cmd_exists pacman;   then PM="pacman"
elif cmd_exists zypper;   then PM="zypper"
elif cmd_exists apk;      then PM="apk"
else
  err "Unsupported system: no known package manager found."
  exit 2
fi
log "Detected package manager: $PM"

# --- Functions per PM --------------------------------------------------------
check_updates() {
  case "$PM" in
    apt)     apt-get update -qq; apt list --upgradable 2>/dev/null || true ;;
    dnf)     dnf -q check-update || true ;;
    yum)     yum -q check-update || true ;;
    pacman)  pacman -Qu || true ;;
    zypper)  zypper -q lu || true ;;
    apk)     apk version -l '<' || true ;;
  esac
}

do_update() {
  case "$PM" in
    apt)
      apt-get update
      if $DIST_UPGRADE; then
        apt-get upgrade -V $YES_FLAG && apt-get dist-upgrade -V $YES_FLAG
      else
        apt-get upgrade -V $YES_FLAG
      fi
      $DO_AUTOREMOVE && { apt-get autoremove $YES_FLAG || true; apt-get autoclean || true; }
      ;;
    dnf)
      dnf upgrade --refresh $YES_FLAG
      $DO_AUTOREMOVE && { dnf autoremove $YES_FLAG || true; }
      ;;
    yum)
      yum update $YES_FLAG
      $DO_AUTOREMOVE && { yum autoremove $YES_FLAG || true; }
      ;;
    pacman)
      pacman -Syu --noconfirm
      # Autoremove is manual on pacman; skipping to avoid unsafe defaults.
      ;;
    zypper)
      zypper refresh
      zypper -n update
      ;;
    apk)
      apk update
      apk upgrade
      ;;
  esac
}

update_snaps() {
  if $DO_SNAP && cmd_exists snap; then
    log "Updating snap packages…"
    snap refresh || err "snap refresh failed (continuing)."
  fi
}

update_flatpak() {
  if $DO_FLATPAK && cmd_exists flatpak; then
    log "Updating flatpak apps/runtimes…"
    flatpak update -y || err "flatpak update failed (continuing)."
  fi
}

needs_reboot() {
  # Debian/Ubuntu
  [[ -f /var/run/reboot-required ]] && return 0
  # RHEL/Fedora (dnf/yum)
  if cmd_exists needs-restarting; then
    needs-restarting -r >/dev/null 2>&1 || return 0
  fi
  return 1
}

# --- Main --------------------------------------------------------------------
if $CHECK_ONLY; then
  log "Listing pending updates (no changes will be made)…"
  check_updates
  if $DO_SNAP && cmd_exists snap; then
    echo
    log "Snap pending updates:"
    snap refresh --list || true
  fi
  if $DO_FLATPAK && cmd_exists flatpak; then
    echo
    log "Flatpak pending updates:"
    flatpak remote-ls --updates || true
  fi
  exit 0
fi

log "Starting system update…"
do_update
update_snaps
update_flatpak
log "Update finished."

if needs_reboot; then
  log "A reboot is required."
  if $DO_REBOOT; then
    log "Rebooting now…"
    /sbin/reboot || reboot
  else
    log "Please reboot the system when convenient."
  fi
else
  log "No reboot required."
fi

exit 0

