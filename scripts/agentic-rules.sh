#!/usr/bin/env bash
# Corpus de règles agentiques Cloud Temple : installation, mise à jour et
# contrôle de conformité dans un dépôt consommateur.
#
#   agentic-rules.sh install <cible> [--ref <tag>] [--source <chemin|url>]
#   agentic-rules.sh update  <cible> [--ref <tag>] [--source <chemin|url>]
#   agentic-rules.sh check   <cible> [--remote]
#
# install refuse d'écraser un corpus déjà présent. update le remplace en
# préservant project.config.yml. check ne touche à rien.
set -euo pipefail

DEFAULT_SOURCE="https://github.com/Cloud-Temple/agentic-rules.git"
PROVENANCE="AGENTIC_RULES/.provenance"
CONFIG="AGENTIC_RULES/project.config.yml"
CONFIG_EXAMPLE="AGENTIC_RULES/project.config.example.yml"

die() { printf 'erreur: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "ni sha256sum ni shasum disponible"; fi
}

# Récupère la source dans un répertoire temporaire et affiche son chemin.
fetch_source() {
  local source="$1" ref="$2" tmp
  tmp="$(mktemp -d)"
  if [ -d "$source/.git" ]; then
    git -C "$source" worktree list >/dev/null 2>&1 || die "source git illisible : $source"
    git clone --quiet --shared "$source" "$tmp/src"
  else
    git clone --quiet "$source" "$tmp/src" || die "clone impossible depuis $source"
  fi
  if [ -n "$ref" ]; then
    git -C "$tmp/src" checkout --quiet "$ref" || die "référence introuvable dans la source : $ref"
  fi
  printf '%s\n' "$tmp/src"
}

read_manifest() {
  grep -v '^[[:space:]]*#' "$1/MANIFEST" | grep -v '^[[:space:]]*$'
}

write_provenance() {
  local src="$1" target="$2" ref commit
  commit="$(git -C "$src" rev-parse HEAD)"
  ref="$(git -C "$src" describe --tags --exact-match 2>/dev/null || echo "sans-tag")"
  {
    printf '# Provenance du corpus de règles agentiques. Fichier généré, ne pas éditer.\n'
    printf 'source_repo=%s\n' "$(git -C "$src" remote get-url origin 2>/dev/null || echo "$DEFAULT_SOURCE")"
    printf 'tag=%s\n' "$ref"
    printf 'commit=%s\n' "$commit"
    printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local f
    while IFS= read -r f; do
      printf 'sha256 %s %s\n' "$f" "$(sha256 "$target/$f")"
    done < <(read_manifest "$src")
  } > "$target/$PROVENANCE"
}

copy_payload() {
  local src="$1" target="$2" f
  while IFS= read -r f; do
    [ -f "$src/$f" ] || die "fichier annoncé au MANIFEST mais absent de la source : $f"
    mkdir -p "$target/$(dirname "$f")"
    cp "$src/$f" "$target/$f"
  done < <(read_manifest "$src")
}

cmd_install() {
  local target="$1" ref="$2" source="$3" src
  [ -d "$target" ] || die "cible inexistante : $target"
  [ -e "$target/$PROVENANCE" ] && die "corpus déjà installé dans $target, utiliser update"
  src="$(fetch_source "$source" "$ref")"
  copy_payload "$src" "$target"
  write_provenance "$src" "$target"
  if [ ! -e "$target/$CONFIG" ]; then
    cp "$target/$CONFIG_EXAMPLE" "$target/$CONFIG"
    info "configuration créée : $CONFIG, renseigner les champs TO_FILL"
  fi
  info "corpus installé dans $target depuis $(grep '^tag=' "$target/$PROVENANCE" | cut -d= -f2)"
}

cmd_update() {
  local target="$1" ref="$2" source="$3" src before after
  [ -e "$target/$PROVENANCE" ] || die "aucun corpus installé dans $target, utiliser install"
  before="$(grep '^commit=' "$target/$PROVENANCE" | cut -d= -f2)"
  src="$(fetch_source "$source" "$ref")"
  copy_payload "$src" "$target"
  write_provenance "$src" "$target"
  after="$(grep '^commit=' "$target/$PROVENANCE" | cut -d= -f2)"
  if [ "$before" = "$after" ]; then
    info "corpus déjà à jour sur $after"
  else
    info "corpus mis à jour : $before -> $after"
  fi
  [ -e "$target/$CONFIG" ] || info "attention : $CONFIG absent, le copier depuis $CONFIG_EXAMPLE"
}

cmd_check() {
  local target="$1" remote="$2" rc=0 path expected actual
  [ -e "$target/$PROVENANCE" ] || die "aucun corpus installé dans $target"

  while read -r _ path expected; do
    if [ ! -f "$target/$path" ]; then
      printf 'MANQUANT   %s\n' "$path"; rc=1; continue
    fi
    actual="$(sha256 "$target/$path")"
    if [ "$actual" != "$expected" ]; then
      printf 'MODIFIE    %s\n' "$path"; rc=1
    fi
  done < <(grep '^sha256 ' "$target/$PROVENANCE")

  if [ -e "$target/$CONFIG" ]; then
    if grep -q 'TO_FILL' "$target/$CONFIG"; then
      printf 'A RENSEIGNER %s contient encore des TO_FILL\n' "$CONFIG"; rc=1
    fi
  else
    printf 'MANQUANT   %s\n' "$CONFIG"; rc=1
  fi

  if [ "$remote" = "yes" ]; then
    local tag latest
    tag="$(grep '^tag=' "$target/$PROVENANCE" | cut -d= -f2)"
    latest="$(git ls-remote --tags --refs "$DEFAULT_SOURCE" 2>/dev/null \
      | awk -F/ '{print $NF}' | sort -V | tail -1 || true)"
    if [ -n "$latest" ] && [ "$tag" != "$latest" ]; then
      printf 'AVERTISSEMENT corpus sur %s, dernier tag publié %s\n' "$tag" "$latest"
    fi
  fi

  if [ "$rc" -eq 0 ]; then info "conforme"; else info "non conforme"; fi
  return "$rc"
}

main() {
  [ $# -ge 2 ] || die "usage: $0 {install|update|check} <cible> [options]"
  local cmd="$1" target="$2"; shift 2
  local ref="" source="$DEFAULT_SOURCE" remote="no"
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref) ref="${2:-}"; shift 2 ;;
      --source) source="${2:-}"; shift 2 ;;
      --remote) remote="yes"; shift ;;
      *) die "option inconnue : $1" ;;
    esac
  done
  case "$cmd" in
    install) cmd_install "$target" "$ref" "$source" ;;
    update)  cmd_update  "$target" "$ref" "$source" ;;
    check)   cmd_check   "$target" "$remote" ;;
    *) die "commande inconnue : $cmd" ;;
  esac
}

main "$@"
