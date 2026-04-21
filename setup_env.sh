#!/usr/bin/env bash
set -euo pipefail

# XM1 environment bootstrap.
# Default behavior:
# - Target Python version: 3.10
# - Prefer uv for env creation
# - Fallback to local python3.10 venv/virtualenv
#
# Usage:
#   bash setup_env.sh
#   bash setup_env.sh --dev
#   bash setup_env.sh --venv .venv310 --python-version 3.10 --manager uv

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR=".venv"
PY_VERSION="3.10"
MANAGER="auto"    # auto|uv|venv
INSTALL_DEV="0"
UV_BIN="${UV_BIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv)
      VENV_DIR="${2:-}"
      shift 2
      ;;
    --python-version)
      PY_VERSION="${2:-}"
      shift 2
      ;;
    --manager)
      MANAGER="${2:-}"
      shift 2
      ;;
    --dev)
      INSTALL_DEV="1"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

REQ_FILE="requirements.txt"
if [[ "${INSTALL_DEV}" == "1" ]]; then
  REQ_FILE="requirements-dev.txt"
fi

if [[ ! -f "${PROJECT_DIR}/${REQ_FILE}" ]]; then
  echo "Error: ${REQ_FILE} not found in ${PROJECT_DIR}"
  exit 1
fi

ENV_PATH="${PROJECT_DIR}/${VENV_DIR}"
PY_BIN_CANDIDATE="python${PY_VERSION}"

choose_manager() {
  if [[ "${MANAGER}" == "uv" || "${MANAGER}" == "venv" ]]; then
    echo "${MANAGER}"
    return
  fi
  if [[ -n "${UV_BIN}" ]]; then
    echo "uv"
  else
    echo "venv"
  fi
}

detect_uv_bin() {
  if [[ -n "${UV_BIN}" ]]; then
    return
  fi
  if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
    return
  fi
  if [[ -x "${HOME}/.local/bin/uv" ]]; then
    UV_BIN="${HOME}/.local/bin/uv"
  fi
}

create_with_uv() {
  if [[ -z "${UV_BIN}" ]]; then
    echo "Error: uv is not installed but manager=uv was requested."
    echo "Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "Or set UV_BIN explicitly, e.g. UV_BIN=\$HOME/.local/bin/uv bash setup_env.sh --manager uv --python-version ${PY_VERSION}"
    exit 1
  fi
  echo "[2/5] Creating ${PY_VERSION} environment via uv (${UV_BIN}) at ${ENV_PATH} ..."
  "${UV_BIN}" venv --python "${PY_VERSION}" "${ENV_PATH}"
}

create_with_venv() {
  if ! command -v "${PY_BIN_CANDIDATE}" >/dev/null 2>&1; then
    echo "Error: ${PY_BIN_CANDIDATE} not found."
    echo "Please install Python ${PY_VERSION} or install uv and rerun."
    echo "Example with uv:"
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "  uv python install ${PY_VERSION}"
    exit 1
  fi

  echo "[2/5] Creating ${PY_VERSION} environment via ${PY_BIN_CANDIDATE} at ${ENV_PATH} ..."
  if ! "${PY_BIN_CANDIDATE}" -m venv "${ENV_PATH}"; then
    echo "venv creation failed. Falling back to virtualenv..."
    if ! "${PY_BIN_CANDIDATE}" -m virtualenv --version >/dev/null 2>&1; then
      "${PY_BIN_CANDIDATE}" -m pip install --upgrade virtualenv
    fi
    "${PY_BIN_CANDIDATE}" -m virtualenv --clear "${ENV_PATH}"
  fi
}

echo "[1/5] Preparing setup..."
detect_uv_bin
SELECTED_MANAGER="$(choose_manager)"
echo "Manager: ${SELECTED_MANAGER}"
echo "Python target: ${PY_VERSION}"
echo "Requirements: ${REQ_FILE}"

if [[ -d "${ENV_PATH}" ]]; then
  echo "Environment exists, reusing: ${ENV_PATH}"
fi

if [[ "${SELECTED_MANAGER}" == "uv" ]]; then
  create_with_uv
else
  create_with_venv
fi

echo "[3/5] Activating environment..."
source "${ENV_PATH}/bin/activate"
python --version

echo "[4/5] Installing dependencies..."
if [[ "${SELECTED_MANAGER}" == "uv" ]]; then
  "${UV_BIN}" pip install --python "${ENV_PATH}/bin/python" --upgrade pip setuptools wheel
  "${UV_BIN}" pip install --python "${ENV_PATH}/bin/python" -r "${PROJECT_DIR}/${REQ_FILE}"
else
  python -m pip install --upgrade pip setuptools wheel
  python -m pip install -r "${PROJECT_DIR}/${REQ_FILE}"
fi

echo "[5/5] Done."
echo "Activate with:"
echo "  source ${ENV_PATH}/bin/activate"
