#!/usr/bin/env bash
set -euo pipefail

# oml-sanity.sh
# Sanity check for monorepo + git submodules:
# - clean working tree (root + submodules)
# - branch sync with origin
# - submodule status aligned (no + - U)
# - optional: verify submodule commits exist in remotes (prevents "not our ref")

FIX=0
CHECK_REMOTES=0
LIST_SUBMODULES=0
JOBS=8

usage() {
  cat <<'EOF'
Uso:
  oml-sanity.sh [--fix] [--check-remotes] [--list-submodules] [--jobs N]

Opciones:
  --fix              Intenta alinear submódulos a lo que espera el repo padre (equivale a submodule sync/update --force).
  --check-remotes    Verifica que cada SHA de submódulo exista en el remoto (evita "not our ref").
  --list-submodules  Lista submódulos (SHA, rama y versión) sin exigir repo limpio ni sincronizado.
  --jobs N           Paralelismo para submodule update (default: 8).

Salida:
  Modo sanity: valida repo padre y submódulos; incluye rama y versión (git describe).
  Modo --list-submodules: solo imprime el estado de submódulos.
  0 = OK
  1 = Problemas detectados
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --check-remotes) CHECK_REMOTES=1; shift ;;
    --list-submodules) LIST_SUBMODULES=1; shift ;;
    --jobs) JOBS="${2:-8}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1"; usage; exit 2 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

list_submodules() {
  if [[ ! -f .gitmodules ]]; then
    echo "No hay .gitmodules."
    return 0
  fi

  echo "Submódulos:"
  SUBSTAT="$(git submodule status || true)"
  echo "$SUBSTAT"
  echo
  echo "Rama / versión:"
  git submodule foreach --quiet 'printf "%-45s %-20s %s\n" "$name" "$(git branch --show-current)" "$(git describe --tags --always)"'
}

# Ensure we're in a git repo (root or inside)
git rev-parse --show-toplevel >/dev/null 2>&1 || die "No estás dentro de un repositorio Git."
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

echo "Repo: $ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
echo "Branch: $BRANCH"
echo "HEAD:   $HEAD_SHA"
echo

if [[ "$LIST_SUBMODULES" -eq 1 ]]; then
  list_submodules
  exit 0
fi

# 1) Root working tree clean?
if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ Repo padre: working tree NO limpio"
  git status --short
  echo
  die "Commit/stash antes de continuar. (Para ver solo submódulos: ./git_sanity.sh --list-submodules)"
else
  echo "✅ Repo padre: working tree limpio"
fi

# 2) Branch sync with origin
# Make sure we have origin info
git fetch -q origin || die "No pude hacer fetch de origin."

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  AHEAD_BEHIND="$(git rev-list --left-right --count "origin/$BRANCH...HEAD" 2>/dev/null || echo "0 0")"
  BEHIND="$(echo "$AHEAD_BEHIND" | awk '{print $1}')"
  AHEAD="$(echo "$AHEAD_BEHIND" | awk '{print $2}')"

  if [[ "$AHEAD" != "0" || "$BEHIND" != "0" ]]; then
    echo "❌ Rama no sincronizada con origin/$BRANCH: ahead=$AHEAD behind=$BEHIND"
    echo "   Ver commits locales no pusheados:"
    git log --oneline "origin/$BRANCH..HEAD" || true
    echo
    die "Sincronizá (push/pull) antes de sanity."
  else
    echo "✅ Rama sincronizada con origin/$BRANCH"
  fi
else
  echo "⚠️ No existe origin/$BRANCH (rama sin tracking remoto)."
  echo "   Si esto es intencional, ignorá. Si no, configurá tracking y pusheá."
fi

# 3) Submodules present?
if [[ ! -f .gitmodules ]]; then
  echo
  echo "✅ No hay .gitmodules. Listo."
  exit 0
fi

echo

# Optional fix: sync + update --force
if [[ "$FIX" -eq 1 ]]; then
  echo "→ --fix: sincronizando URLs y alineando submódulos..."
  git submodule sync --recursive
  git submodule update --init --recursive --force --jobs "$JOBS"
  echo "→ --fix: terminado."
fi

# 4) Submodule status aligned?
list_submodules

# Identify problematic prefixes: '+', '-', 'U'
if echo "$SUBSTAT" | grep -Eq '^[\+\-U]'; then
  echo
  echo "❌ Hay submódulos desalineados/no init/conflict (prefijo + - U)."
  echo "   Sugerencia: ejecutá: git submodule update --init --recursive --force"
  exit 1
else
  echo "✅ Submódulos alineados (sin + - U)"
fi

# 5) Submodule working trees clean?
echo
echo "Chequeando working tree de submódulos..."
DIRTY_SM="$(git submodule foreach --quiet 'test -z "$(git status --porcelain)" || echo "$name"' || true)"
if [[ -n "$DIRTY_SM" ]]; then
  echo "❌ Submódulos con cambios locales:"
  echo "$DIRTY_SM"
  echo
  exit 1
else
  echo "✅ Submódulos con working tree limpio"
fi

# 6) Optional: verify each submodule commit exists in remote
if [[ "$CHECK_REMOTES" -eq 1 ]]; then
  echo
  echo "Verificando que los SHAs de submódulos existan en sus remotos (puede tardar)..."

  # Parse .gitmodules to get path + url
  # For each submodule, check if remote advertises object (fetch --dry-run will fail if not)
  # We'll use: git -C <path> fetch --dry-run origin <sha>
  FAIL=0

  while IFS= read -r line; do
    # line format: "<sha> <path> (desc)"
    sha="$(echo "$line" | awk '{print $1}')"
    path="$(echo "$line" | awk '{print $2}')"

    # Skip empty
    [[ -z "$sha" || -z "$path" ]] && continue

    # In submodule, origin should exist. Dry-run fetch specific sha.
    if ! git -C "$path" fetch -q --dry-run origin "$sha" >/dev/null 2>&1; then
      echo "❌ $path: commit $sha NO está disponible en origin (posible 'not our ref')"
      FAIL=1
    else
      echo "✅ $path: commit $sha OK en origin"
    fi
  done < <(echo "$SUBSTAT")

  if [[ "$FAIL" -ne 0 ]]; then
    echo
    die "Hay commits de submódulo no publicados. Publicalos (push a rama/tag) o corregí el puntero en el repo padre."
  fi
fi

echo
echo "✅ SANITY OK: repo padre y submódulos están listos."
exit 0
