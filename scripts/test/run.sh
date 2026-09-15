#!/usr/bin/env bash
# Tests du script agentic-rules.sh.
#
# Chaque test construit une source git isolée à partir de l'arbre de travail
# courant, puis exerce install, update et check sur un dépôt consommateur
# jetable. Aucun accès réseau, aucune dépendance à l'état du dépôt appelant.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/agentic-rules.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); printf '  KO   %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (attendu «$3», obtenu «$2»)"; fi; }

# Source git isolée : copie de l'arbre courant, commit unique, tag.
make_source() {
  local dir="$1"
  mkdir -p "$dir"
  tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$dir" -xf -
  git -C "$dir" init --quiet -b main
  git -C "$dir" add -A
  git -C "$dir" -c user.email=test@local -c user.name=test commit --quiet -m "source de test"
  git -C "$dir" tag v0.0.0-test
  git -C "$dir" remote add origin https://example.invalid/agentic-rules.git
}

fill_config() {
  sed -i'' -e 's/TO_FILL/valeur-test/g' "$1/AGENTIC_RULES/project.config.yml"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/source"
make_source "$SRC"

printf 'install\n'
T="$WORK/c1"; mkdir -p "$T"
out="$("$SCRIPT" install "$T" --ref v0.0.0-test --source "$SRC" 2>&1)"; rc=$?
check "install réussit" "$rc" "0"
[ -f "$T/AGENTIC_RULES/MAIN_RULES.md" ] && ok "règles copiées" || ko "règles copiées"
[ -f "$T/AGENTS.md" ] && [ -f "$T/CLAUDE.md" ] && [ -f "$T/QWEN.md" ] && ok "fichiers d'amorçage copiés" || ko "fichiers d'amorçage copiés"
[ -f "$T/AGENTIC_RULES/.provenance" ] && ok "provenance écrite" || ko "provenance écrite"
grep -q "^tag=v0.0.0-test" "$T/AGENTIC_RULES/.provenance" && ok "provenance nomme le tag" || ko "provenance nomme le tag"
[ -f "$T/AGENTIC_RULES/project.config.yml" ] && ok "configuration créée" || ko "configuration créée"
grep -q "sha256 AGENTIC_RULES/project.config.yml " "$T/AGENTIC_RULES/.provenance" \
  && ko "la configuration ne doit pas être empreintée" || ok "la configuration reste hors empreinte"

printf 'check\n'
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un TO_FILL non renseigné échoue" "$rc" "1"
fill_config "$T"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "conforme après renseignement" "$rc" "0"

printf 'dérive\n'
printf '\nrègle locale ajoutée\n' >> "$T/AGENTIC_RULES/MAIN_RULES.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un fichier modifié échoue" "$rc" "1"
printf '%s' "$out" | grep -q "MODIFIE    AGENTIC_RULES/MAIN_RULES.md" && ok "le fichier modifié est nommé" || ko "le fichier modifié est nommé"
rm "$T/AGENTIC_RULES/WORKFLOW_GIT.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un fichier supprimé échoue" "$rc" "1"
printf '%s' "$out" | grep -q "MANQUANT   AGENTIC_RULES/WORKFLOW_GIT.md" && ok "le fichier manquant est nommé" || ko "le fichier manquant est nommé"

printf 'update\n'
out="$("$SCRIPT" update "$T" --ref v0.0.0-test --source "$SRC" 2>&1)"; rc=$?
check "update réussit" "$rc" "0"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "update répare la dérive" "$rc" "0"
grep -q "valeur-test" "$T/AGENTIC_RULES/project.config.yml" && ok "update préserve la configuration" || ko "update préserve la configuration"

printf 'refus\n'
"$SCRIPT" install "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse un corpus déjà présent" "$rc" "1"
T2="$WORK/c2"; mkdir -p "$T2"
"$SCRIPT" update "$T2" --source "$SRC" >/dev/null 2>&1; rc=$?
check "update refuse un dépôt sans corpus" "$rc" "1"
"$SCRIPT" check "$T2" >/dev/null 2>&1; rc=$?
check "check refuse un dépôt sans corpus" "$rc" "1"
"$SCRIPT" install "$WORK/inexistant" --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse une cible inexistante" "$rc" "1"
"$SCRIPT" install "$T2" --ref v9.9.9-absent --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse une référence inconnue" "$rc" "1"
[ -e "$T2/AGENTIC_RULES/.provenance" ] && ko "échec de référence ne doit rien installer" || ok "échec de référence n'installe rien"

printf '\n%d succès, %d échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
