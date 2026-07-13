#!/bin/bash
# Checkout opcional de OMLOSS_BRANCH (p. ej. probar otra rama en deploy manual).
set -euo pipefail

branch="${OMLOSS_BRANCH:-}"
if [ -z "$branch" ]; then
  exit 0
fi

_oml_ci_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${_oml_ci_script_dir}/lib.sh"
oml_ci_init_paths

cd "$CI_PROJECT_DIR"

if [ "$branch" = "${CI_COMMIT_REF_NAME:-}" ]; then
  echo "OMLOSS_BRANCH=${branch} coincide con CI_COMMIT_REF_NAME; omitiendo git checkout"
  exit 0
fi

echo "Checkout OMLOSS_BRANCH=${branch} (pipeline en ${CI_COMMIT_REF_NAME:-detached})"
git fetch origin "$branch"
git checkout -f -B "$branch" "origin/${branch}"
