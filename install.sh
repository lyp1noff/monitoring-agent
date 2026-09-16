#!/usr/bin/env bash
set -euo pipefail

repo_url=https://github.com/lyp1noff/monitoring-agent.git
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# When fetched from GitHub, install the repository first, then use its local script.
if [[ ! -f "$script_dir/compose.yml" || ! -f "$script_dir/config.alloy" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    printf 'Git is required to download the monitoring-agent repository.\n' >&2
    exit 1
  fi
  install_dir=${MONITORING_AGENT_DIR:-"$PWD/monitoring-agent"}
  if [[ ! -d "$install_dir/.git" ]]; then
    if [[ -e "$install_dir" ]]; then
      printf 'Install path already exists and is not a Git repository: %s\n' "$install_dir" >&2
      exit 1
    fi
    git clone "$repo_url" "$install_dir"
  fi
  if [[ ! -f "$install_dir/install.sh" || ! -f "$install_dir/compose.yml" ]]; then
    printf 'Missing monitoring-agent files in %s\n' "$install_dir" >&2
    exit 1
  fi
  exec bash "$install_dir/install.sh" "$@"
fi

cd "$script_dir"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--hostname NAME] [--environment NAME] [--site NAME]
                    [--role NAME] [--prometheus-url URL] [--ui|--no-ui]

With a terminal, missing values are prompted. Without a terminal, defaults are used.
Existing .env values are kept when the matching argument is omitted.
EOF
}

instance_arg= environment_arg= site_arg= role_arg= url_arg= ui_arg=
while (($#)); do
  case "$1" in
    --hostname|--environment|--site|--role|--prometheus-url)
      if (($# < 2)) || [[ -z "$2" ]]; then
        printf 'Missing value for %s\n' "$1" >&2
        exit 2
      fi
      case "$1" in
        --hostname) instance_arg=$2 ;;
        --environment) environment_arg=$2 ;;
        --site) site_arg=$2 ;;
        --role) role_arg=$2 ;;
        --prometheus-url) url_arg=$2 ;;
      esac
      shift 2
      ;;
    --ui) ui_arg=127.0.0.1:12345; shift ;;
    --no-ui) ui_arg=127.0.0.1:0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required. Install Docker Engine first.\n' >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  printf 'Docker Compose v2 is required (docker compose).\n' >&2
  exit 1
fi
if [[ ! -e /run/udev/data ]]; then
  printf '/run/udev/data is missing; this template requires udev data on the host.\n' >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  chmod 600 .env
fi

read_env() {
  local key=$1
  sed -n "s/^${key}=//p" .env | tail -n 1
}

choose() {
  local value=$1 default=$2 prompt=$3
  if [[ -z "$value" ]]; then
    value=$default
    if [[ -t 0 ]]; then
      read -r -p "$prompt [$default]: " answer
      value=${answer:-$default}
    fi
  fi
  printf '%s' "$value"
}

instance=$(choose "$instance_arg" "$(read_env INSTANCE)" 'Hostname')
environment=$(choose "$environment_arg" "$(read_env ENVIRONMENT)" 'Environment')
site=$(choose "$site_arg" "$(read_env SITE)" 'Site')
role=$(choose "$role_arg" "$(read_env ROLE)" 'Role')
url=$(choose "$url_arg" "$(read_env PROMETHEUS_URL)" 'Prometheus remote_write URL')
ui_addr=${ui_arg:-$(read_env ALLOY_HTTP_LISTEN_ADDR)}
ui_addr=${ui_addr:-127.0.0.1:0}

for value in "$instance" "$environment" "$site" "$role"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    printf 'Labels must be nonempty and contain only letters, digits, _, . or -.\n' >&2
    exit 2
  fi
done
if [[ ! "$url" =~ ^https?://[A-Za-z0-9._~:/?\&=%+-]+$ ]]; then
  printf 'Prometheus URL must be an HTTP(S) URL without spaces or shell-special characters.\n' >&2
  exit 2
fi
if [[ "$url" == http://prometheus.example.com:9090/api/v1/write ]]; then
  printf 'Set --prometheus-url to your actual Prometheus receiver URL.\n' >&2
  exit 2
fi
if [[ "$ui_addr" != 127.0.0.1:0 && "$ui_addr" != 127.0.0.1:12345 ]]; then
  printf 'ALLOY_HTTP_LISTEN_ADDR must be 127.0.0.1:0 or 127.0.0.1:12345.\n' >&2
  exit 2
fi

tmp_env=$(mktemp .env.XXXXXX)
trap 'rm -f "$tmp_env"' EXIT
chmod 600 "$tmp_env"
printf 'INSTANCE=%s\nENVIRONMENT=%s\nSITE=%s\nROLE=%s\nPROMETHEUS_URL=%s\nALLOY_HTTP_LISTEN_ADDR=%s\n' \
  "$instance" "$environment" "$site" "$role" "$url" "$ui_addr" > "$tmp_env"
mv "$tmp_env" .env
trap - EXIT

mkdir -p data
docker compose config --quiet
docker compose up -d
printf 'Alloy started for %s. Check: docker compose ps; docker compose logs --tail=50 alloy\n' "$instance"
if [[ "$ui_addr" == 127.0.0.1:12345 ]]; then
  printf 'Alloy UI: http://127.0.0.1:12345/ (on this server only)\n'
fi
