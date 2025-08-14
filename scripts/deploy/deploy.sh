#!/usr/bin/env bash
# deploy.sh — Zero-downtime(ish) deployment helper for Linux hosts.
# Features
# - Versioned releases: /var/www/<app>/releases/<ts> with symlink /var/www/<app>/current
# - Atomic switch via symlink + optional systemd reload/restart
# - Health check with automatic rollback on failure
# - Optional Docker Compose mode (build/pull/up) instead of systemd service
# - Idempotent and heavily logged
#
# Usage:
#   ./deploy.sh --artifact PATH|--repo URL --ref main \
#               --app myapp --root /var/www --health-url http://127.0.0.1:8080/health \
#               [--systemd myapp.service] [--compose docker-compose.yml] [--compose-project myapp] \
#               [--timeout 30] [--keep 5] [--env-file .env] [--pre "cmd"] [--post "cmd"] [-y]
#
# Exit codes: 0 ok, 1 usage error, 2 deploy failed, 3 health failed/rolled back

set -euo pipefail

# -------- Defaults --------
APP=""
ROOT="/var/www"
KEEP=5
TIMEOUT=30
ARTIFACT=""
REPO=""
REF="main"
SYSTEMD=""
HEALTH_URL=""
ENV_FILE=""
PRE_HOOK=""
POST_HOOK=""
COMPOSE_FILE=""
COMPOSE_PROJECT=""
ASSUME_YES=false

log(){ printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }
err(){ printf "[%s] ERROR: %s\n" "$(date '+%F %T')" "$*" >&2; }
die(){ err "$*"; exit 1; }
cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

usage(){
cat <<EOF
deploy.sh - simple deployment helper

Required:
  --app NAME                      Application name
  --health-url URL                Health URL to verify after switch
  One of:
    --artifact PATH               Tarball (.tar.gz) or directory with built app
    --repo URL [--ref BRANCH]     Git repo and ref to build/copy (expects build script within)

Optional:
  --root DIR                      Base dir (default: /var/www)
  --systemd UNIT                  Systemd unit to restart/reload
  --compose FILE                  docker-compose.yml to use (switch to compose mode)
  --compose-project NAME          Compose project name (default: APP)
  --env-file FILE                 .env to copy into release (if present)
  --pre "CMD"                     Pre-deploy hook (runs in new release dir)
  --post "CMD"                    Post-deploy hook (runs after switch)
  --timeout SECS                  Health timeout (default: 30)
  --keep N                        Releases to keep (default: 5)
  -y                              Assume yes for prompts
EOF
}

# -------- Parse args --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift ;;
    --root) ROOT="$2"; shift ;;
    --artifact) ARTIFACT="$2"; shift ;;
    --repo) REPO="$2"; shift ;;
    --ref) REF="$2"; shift ;;
    --systemd) SYSTEMD="$2"; shift ;;
    --health-url) HEALTH_URL="$2"; shift ;;
    --env-file) ENV_FILE="$2"; shift ;;
    --pre) PRE_HOOK="$2"; shift ;;
    --post) POST_HOOK="$2"; shift ;;
    --timeout) TIMEOUT="$2"; shift ;;
    --keep) KEEP="$2"; shift ;;
    --compose) COMPOSE_FILE="$2"; shift ;;
    --compose-project) COMPOSE_PROJECT="$2"; shift ;;
    -y) ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac; shift
done

[[ -n "$APP" && -n "$HEALTH_URL" ]] || die "Missing required --app and/or --health-url"
if [[ -z "$ARTIFACT" && -z "$REPO" ]]; then die "Provide --artifact or --repo"; fi
APP_DIR="$ROOT/$APP"
REL_DIR="$APP_DIR/releases"
TS="$(date +%Y%m%d%H%M%S)"
NEW_REL="$REL_DIR/$TS"
CURR="$APP_DIR/current"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-$APP}"

# -------- Prepare dirs --------
log "Preparing directories under $APP_DIR"
sudo mkdir -p "$REL_DIR"
sudo chown -R "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$APP_DIR"

# -------- Fetch/build release --------
log "Creating release: $NEW_REL"
mkdir -p "$NEW_REL"

if [[ -n "$ARTIFACT" ]]; then
  if [[ -f "$ARTIFACT" && "$ARTIFACT" == *.tar.gz ]]; then
    tar -xzf "$ARTIFACT" -C "$NEW_REL"
  elif [[ -d "$ARTIFACT" ]]; then
    rsync -a --delete "$ARTIFACT"/ "$NEW_REL"/
  else
    die "Invalid --artifact path"
  fi
else
  cmd_exists git || die "git not found"
  git clone --depth 1 --branch "$REF" "$REPO" "$NEW_REL/src"
  if [[ -x "$NEW_REL/src/build.sh" ]]; then
    (cd "$NEW_REL/src" && ./build.sh)
  fi
  if [[ -d "$NEW_REL/src/dist" ]]; then
    rsync -a "$NEW_REL/src/dist"/ "$NEW_REL"/
  else
    rsync -a --exclude ".git" "$NEW_REL/src"/ "$NEW_REL"/
  fi
  rm -rf "$NEW_REL/src"
fi

# Copy env file if provided
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  cp "$ENV_FILE" "$NEW_REL/.env"
fi

# -------- Pre hook --------
if [[ -n "$PRE_HOOK" ]]; then
  log "Running pre-deploy hook"
  (cd "$NEW_REL" && bash -lc "$PRE_HOOK")
fi

# -------- Start/Reload new release (compose/systemd/none) --------
start_new_release(){
  if [[ -n "$COMPOSE_FILE" ]]; then
    cmd_exists docker || die "docker not found"
    cmd_exists docker-compose || cmd_exists docker compose || die "docker compose not found"
    log "Starting via Docker Compose ($COMPOSE_FILE) project=$COMPOSE_PROJECT"
    # Use per-release override to point to this release
    cp "$COMPOSE_FILE" "$NEW_REL/docker-compose.yml"
    (cd "$NEW_REL" && docker compose -p "$COMPOSE_PROJECT" -f docker-compose.yml pull)
    (cd "$NEW_REL" && docker compose -p "$COMPOSE_PROJECT" -f docker-compose.yml up -d --build)
  elif [[ -n "$SYSTEMD" ]]; then
    log "Reloading systemd unit: $SYSTEMD"
    sudo systemctl daemon-reload || true
    sudo systemctl restart "$SYSTEMD"
  else
    log "No process manager configured; assuming external supervisor."
  fi
}

# -------- Health check --------
health_check(){
  log "Health checking $HEALTH_URL (timeout ${TIMEOUT}s)"
  local t=0
  until curl -fsS "$HEALTH_URL" >/dev/null 2>&1; do
    sleep 1; t=$((t+1))
    if (( t >= TIMEOUT )); then
      return 1
    fi
  done
  return 0
}

# -------- Switch symlink atomically --------
log "Linking new release"
ln -sfn "$NEW_REL" "$CURR"

start_new_release
if ! health_check; then
  err "Health check failed; rolling back"
  # rollback to previous
  PREV="$(ls -dt "$REL_DIR"/* | sed -n '2p' || true)"
  if [[ -n "$PREV" && -d "$PREV" ]]; then
    ln -sfn "$PREV" "$CURR"
    start_new_release || true
  fi
  exit 3
fi

# -------- Post hook --------
if [[ -n "$POST_HOOK" ]]; then
  log "Running post-deploy hook"
  (cd "$CURR" && bash -lc "$POST_HOOK")
fi

# -------- Cleanup old releases --------
log "Cleaning old releases (keep $KEEP)"
(ls -dt "$REL_DIR"/* 2>/dev/null | sed -n "1,${KEEP}p"; ls -dt "$REL_DIR"/* 2>/dev/null | sed -n "$((KEEP+1)),999p") >/tmp/releases_list.$$ || true
mapfile -t TO_KEEP < <(sed -n "1,${KEEP}p" /tmp/releases_list.$$ || true)
mapfile -t TO_DELETE < <(sed -n "$((KEEP+1)),999p" /tmp/releases_list.$$ || true)
for d in "${TO_DELETE[@]:-}"; do
  rm -rf "$d"
done
rm -f /tmp/releases_list.$$

log "Deployment completed successfully"

