#!/bin/bash
# Instala dependencias de Ansible/OMniLeads para jobs de GitLab CI.
# Funciona en imagen Docker (python:3.11-slim) y en shell/SSH executor del runner.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
oml_ci_init_paths

DOCTL_VERSION="${DOCTL_VERSION:-1.118.0}"
VENV_DIR="${ANSIBLE_DIR}/.ci-venv"

cd "$ANSIBLE_DIR"

ci_has_prereqs() {
  command -v python3 >/dev/null 2>&1 \
    && command -v git >/dev/null 2>&1 \
    && command -v curl >/dev/null 2>&1 \
    && { command -v ssh >/dev/null 2>&1 || command -v ssh-add >/dev/null 2>&1; } \
    && { python3 -c "import venv" 2>/dev/null || python3 -m pip --version >/dev/null 2>&1; }
}

run_apt_with_retry() {
  local attempt=1
  local max="${OML_CI_APT_RETRIES:-5}"
  local wait_s="${OML_CI_APT_RETRY_WAIT:-15}"

  while [ "$attempt" -le "$max" ]; do
    if "$@"; then
      return 0
    fi
    echo "apt command failed (attempt ${attempt}/${max}), retrying in ${wait_s}s..." >&2
    sleep "$wait_s"
    attempt=$((attempt + 1))
  done
  return 1
}

install_apt_packages() {
  if [ "${OML_CI_SKIP_APT:-}" = "1" ]; then
    echo "OML_CI_SKIP_APT=1, skipping apt"
    return 0
  fi

  if ci_has_prereqs; then
    echo "Host prerequisites OK (python3, git, curl, ssh, pip/venv); skipping apt"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    if ci_has_prereqs; then
      return 0
    fi
    echo "ERROR: apt-get not available and prerequisites are missing." >&2
    exit 1
  fi

  local pkgs=(openssh-client git curl ca-certificates)
  if ! python3 -c "import venv" 2>/dev/null; then
    pkgs+=(python3-venv python3-pip)
  fi

  local apt_cmd=()
  if [ "$(id -u)" -eq 0 ]; then
    apt_cmd=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    apt_cmd=(sudo apt-get)
  else
    echo "WARNING: cannot run apt-get (not root, no sudo); checking prerequisites only" >&2
    ci_has_prereqs || exit 1
    return 0
  fi

  if ! run_apt_with_retry "${apt_cmd[@]}" -o 'DPkg::Lock::Timeout=120' update -qq; then
    if ci_has_prereqs; then
      echo "WARNING: apt update failed (lock held?) but prerequisites are present; continuing" >&2
      return 0
    fi
    echo "ERROR: apt update failed and prerequisites are missing." >&2
    exit 1
  fi

  if ! run_apt_with_retry env DEBIAN_FRONTEND=noninteractive "${apt_cmd[@]}" -o 'DPkg::Lock::Timeout=120' install -y -qq "${pkgs[@]}"; then
    if ci_has_prereqs; then
      echo "WARNING: apt install failed but prerequisites are present; continuing" >&2
      return 0
    fi
    echo "ERROR: apt install failed and prerequisites are missing." >&2
    exit 1
  fi
}

install_doctl() {
  if [ "${OML_CI_SKIP_DOCTL:-}" = "1" ]; then
    echo "OML_CI_SKIP_DOCTL=1, skipping doctl"
    return 0
  fi

  local doctl_bin="${HOME}/.local/bin/doctl"
  if [ -x "$doctl_bin" ] && "$doctl_bin" version >/dev/null 2>&1; then
    return 0
  fi

  if command -v doctl >/dev/null 2>&1 && doctl version >/dev/null 2>&1; then
    case "$(command -v doctl)" in
      /snap/*) ;;
      *) return 0 ;;
    esac
    echo "doctl snap is broken in CI; installing binary to ${doctl_bin}" >&2
  fi

  local arch tmp
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Unsupported architecture for doctl: $arch" >&2
      exit 1
      ;;
  esac

  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-${arch}.tar.gz" \
    | tar -xz -C "$tmp"
  mkdir -p "${HOME}/.local/bin"
  install -m 0755 "$tmp/doctl" "$doctl_bin"
  rm -rf "$tmp"
}

setup_python_env() {
  if [ ! -d "$VENV_DIR" ]; then
    if python3 -m venv "$VENV_DIR"; then
      :
    else
      echo "python3 -m venv failed; falling back to pip --user" >&2
      export PATH="${HOME}/.local/bin:${PATH}"
      python3 -m pip install --user --upgrade pip
      python3 -m pip install --user -r requirements.txt
      ansible-galaxy collection install -r requirements.yml
      return 0
    fi
  fi

  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r requirements.txt
  ansible-galaxy collection install -r requirements.yml
}

install_apt_packages
install_doctl
setup_python_env

if [ -d "$VENV_DIR" ]; then
  echo "Ansible CI venv: $VENV_DIR"
  echo "CI project root: $CI_PROJECT_DIR"
  "$VENV_DIR/bin/ansible" --version | head -1
else
  ansible --version | head -1
fi

if [ "${OML_CI_SKIP_DOCTL:-}" != "1" ]; then
  doctl version
fi
