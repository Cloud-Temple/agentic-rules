#!/usr/bin/env bash
# Tests du script de distribution du corpus.
#
# Chaque test construit une source git isolée à partir de l'arbre de travail
# courant, avec deux versions taggées, puis exerce install, update et check sur
# des dépôts consommateurs jetables. Aucun accès réseau, aucune dépendance à
# l'état du dépôt appelant. Les chemins contiennent volontairement une espace.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/AGENTIC_RULES/agentic-rules.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
ko()   { FAIL=$((FAIL+1)); printf '  KO   %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (attendu «$3», obtenu «$2»)"; fi; }

git_c() { git -C "$1" -c user.email=test@local -c user.name=test "${@:2}"; }

# Source git isolée. v0.0.0-test est l'état courant ; v0.0.1-test modifie un
# fichier du corpus et en retire un autre, pour exercer une vraie montée de
# version et la suppression d'un fichier sorti de la charge utile.
make_source() {
  local dir="$1"
  mkdir -p "$dir"
  tar -C "$ROOT" --exclude=.git -cf - . | tar -C "$dir" -xf -
  git -C "$dir" init --quiet -b main
  git_c "$dir" add -A
  git_c "$dir" commit --quiet -m "source de test"
  git -C "$dir" tag v0.0.0-test
  printf '\nligne ajoutee en v0.0.1\n' >> "$dir/AGENTIC_RULES/REVIEWERS.md"
  rm "$dir/QWEN.md"
  grep -v '^QWEN.md$' "$dir/AGENTIC_RULES/MANIFEST" > "$dir/AGENTIC_RULES/MANIFEST.tmp"
  mv "$dir/AGENTIC_RULES/MANIFEST.tmp" "$dir/AGENTIC_RULES/MANIFEST"
  git_c "$dir" add -A
  git_c "$dir" commit --quiet -m "v0.0.1 de test"
  git -C "$dir" tag v0.0.1-test
  git -C "$dir" checkout --quiet main
  git -C "$dir" remote add origin https://example.invalid/agentic-rules.git
}

# Renseigne les valeurs seulement. Les commentaires restent intacts : c'est le
# cas réel d'un dépôt correctement configuré.
fill_values() {
  sed -i'' -e 's/: TO_FILL/: valeur-test/' "$1/AGENTIC_RULES/project.config.yml"
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/agentic test XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/source git"
make_source "$SRC"

printf 'install\n'
T="$WORK/depot un"; mkdir -p "$T"
"$SCRIPT" install "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "install réussit" "$rc" "0"
[ -f "$T/AGENTIC_RULES/MAIN_RULES.md" ] && ok "règles copiées" || ko "règles copiées"
[ -f "$T/AGENTS.md" ] && [ -f "$T/CLAUDE.md" ] && [ -f "$T/QWEN.md" ] && ok "fichiers d'amorçage copiés" || ko "fichiers d'amorçage copiés"
[ -x "$T/AGENTIC_RULES/agentic-rules.sh" ] && ok "script vendoré et exécutable" || ko "script vendoré et exécutable"
[ -f "$T/AGENTIC_RULES/MANIFEST" ] && ok "MANIFEST vendoré" || ko "MANIFEST vendoré"
grep -q "^tag=v0.0.0-test" "$T/AGENTIC_RULES/.provenance" && ok "provenance nomme le tag" || ko "provenance nomme le tag"
grep -q "sha256 AGENTIC_RULES/project.config.yml " "$T/AGENTIC_RULES/.provenance" \
  && ko "la configuration ne doit pas être empreintée" || ok "la configuration reste hors empreinte"

printf 'configuration\n'
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un TO_FILL non renseigné échoue" "$rc" "1"
fill_values "$T"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "conforme quand seules les valeurs sont renseignées" "$rc" "0"
printf '# note libre mentionnant TO_FILL dans un commentaire\n' >> "$T/AGENTIC_RULES/project.config.yml"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un TO_FILL en commentaire ne fait pas échouer" "$rc" "0"

printf 'dérive\n'
printf '\nrègle locale ajoutée\n' >> "$T/AGENTIC_RULES/MAIN_RULES.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un fichier modifié échoue" "$rc" "1"
printf '%s' "$out" | grep -q "MODIFIE    AGENTIC_RULES/MAIN_RULES.md" && ok "le fichier modifié est nommé" || ko "le fichier modifié est nommé"
"$SCRIPT" update "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
rm "$T/AGENTIC_RULES/WORKFLOW_GIT.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un fichier supprimé échoue" "$rc" "1"
printf '%s' "$out" | grep -q "MANQUANT   AGENTIC_RULES/WORKFLOW_GIT.md" && ok "le fichier manquant est nommé" || ko "le fichier manquant est nommé"
"$SCRIPT" update "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1

printf 'contournements\n'
printf 'regle locale du depot\n' > "$T/AGENTIC_RULES/LOCAL_RULES.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "une règle locale ajoutée échoue" "$rc" "1"
printf '%s' "$out" | grep -q "AJOUT LOCAL" && ok "l'ajout local est nommé" || ko "l'ajout local est nommé"
rm "$T/AGENTIC_RULES/LOCAL_RULES.md"
cp "$T/AGENTIC_RULES/.provenance" "$WORK/prov.bak"
grep -v '^sha256 ' "$WORK/prov.bak" > "$T/AGENTIC_RULES/.provenance"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "une provenance vidée de ses empreintes échoue" "$rc" "1"
cp "$WORK/prov.bak" "$T/AGENTIC_RULES/.provenance"
printf '\nmodification masquee\n' >> "$T/AGENTIC_RULES/REVIEWERS.md"
grep -v '^AGENTIC_RULES/REVIEWERS.md$' "$WORK/prov.bak" > /dev/null
grep -v '^AGENTIC_RULES/REVIEWERS.md$' "$T/AGENTIC_RULES/MANIFEST" > "$T/AGENTIC_RULES/MANIFEST.tmp"
mv "$T/AGENTIC_RULES/MANIFEST.tmp" "$T/AGENTIC_RULES/MANIFEST"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "retirer un fichier du MANIFEST ne le sort pas du contrôle" "$rc" "1"
printf '%s' "$out" | grep -q "HORS MANIFEST" && ok "l'empreinte orpheline est nommée" || ko "l'empreinte orpheline est nommée"
"$SCRIPT" update "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "update répare tout" "$rc" "0"
grep -q "valeur-test" "$T/AGENTIC_RULES/project.config.yml" && ok "update préserve la configuration" || ko "update préserve la configuration"

printf 'montée de version\n'
before="$(grep '^commit=' "$T/AGENTIC_RULES/.provenance" | cut -d= -f2)"
"$SCRIPT" update "$T" --ref v0.0.1-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "update vers une autre version réussit" "$rc" "0"
after="$(grep '^commit=' "$T/AGENTIC_RULES/.provenance" | cut -d= -f2)"
[ "$before" != "$after" ] && ok "la provenance change de commit" || ko "la provenance change de commit"
grep -q "^tag=v0.0.1-test" "$T/AGENTIC_RULES/.provenance" && ok "la provenance change de tag" || ko "la provenance change de tag"
grep -q "ligne ajoutee en v0.0.1" "$T/AGENTIC_RULES/REVIEWERS.md" && ok "le contenu est bien celui de la nouvelle version" || ko "le contenu est bien celui de la nouvelle version"
[ -e "$T/QWEN.md" ] && ko "un fichier sorti de la charge utile est retiré" || ok "un fichier sorti de la charge utile est retiré"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "conforme après montée de version" "$rc" "0"

printf 'refus et non-destruction\n'
"$SCRIPT" install "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse un corpus déjà présent" "$rc" "1"
T2="$WORK/depot deux"; mkdir -p "$T2"
"$SCRIPT" update "$T2" --source "$SRC" >/dev/null 2>&1; rc=$?
check "update refuse un dépôt sans corpus" "$rc" "1"
"$SCRIPT" check "$T2" >/dev/null 2>&1; rc=$?
check "check refuse un dépôt sans corpus" "$rc" "1"
printf 'instructions maison a ne pas perdre\n' > "$T2/AGENTS.md"
"$SCRIPT" install "$T2" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse d'écraser un fichier existant" "$rc" "1"
grep -q "instructions maison" "$T2/AGENTS.md" && ok "le fichier existant est intact" || ko "le fichier existant est intact"
[ -e "$T2/AGENTIC_RULES" ] && ko "un refus ne doit rien créer" || ok "un refus ne crée rien"
"$SCRIPT" install "$T2" --ref v0.0.0-test --source "$SRC" --force >/dev/null 2>&1; rc=$?
check "--force installe malgré le conflit" "$rc" "0"
T3="$WORK/depot trois"; mkdir -p "$T3"
printf 'contenu\n' > "$T3/temoin.txt"
"$SCRIPT" install "$T3" --ref v9.9.9-absent --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse une référence inconnue" "$rc" "1"
[ "$(cd "$T3" && find . -mindepth 1 | sort | tr '\n' ' ')" = "./temoin.txt " ] \
  && ok "une référence inconnue laisse la cible strictement inchangée" \
  || ko "une référence inconnue laisse la cible strictement inchangée"
"$SCRIPT" install "$T3" --ref v0.0.0-test --source "$WORK/source inexistante" >/dev/null 2>&1; rc=$?
check "install refuse une source injoignable" "$rc" "1"
[ "$(cd "$T3" && find . -mindepth 1 | sort | tr '\n' ' ')" = "./temoin.txt " ] \
  && ok "une source injoignable laisse la cible strictement inchangée" \
  || ko "une source injoignable laisse la cible strictement inchangée"

printf 'propreté\n'
TMPD="$WORK/tmp"; mkdir -p "$TMPD"
T4="$WORK/depot quatre"; mkdir -p "$T4"
TMPDIR="$TMPD" "$SCRIPT" install "$T4" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
[ -z "$(ls -A "$TMPD")" ] && ok "aucun temporaire laissé derrière" || ko "aucun temporaire laissé derrière"

printf '\n%d succès, %d échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
