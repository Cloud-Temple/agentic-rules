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

# Empreinte complète d'une cible : contenu de chaque fichier et arborescence.
# Ce harnais reste lié à GNU, et l'assumer : `-printf` et `sha256sum` n'existent
# pas partout. Mais une empreinte vide rendrait identiques deux cibles
# quelconques, et les quatre comparaisons qui l'utilisent passeraient sans rien
# comparer. Échouer bruyamment plutôt que silencieusement. Aucune des cibles
# comparées n'est légitimement vide.
snapshot() {
  local tree sums
  # La moitié arborescence est celle qui dépend de `-printf`. Si elle se tait,
  # les comparaisons ne portent plus que sur le contenu des fichiers, et un
  # changement de type, de mode ou de structure passe inaperçu. Le garde-fou
  # porte donc sur elle, pas sur la concaténation des deux : la moitié empreinte
  # continue de produire des lignes et masquerait le silence de la première.
  # La fonction rend un code, elle ne quitte pas : appelée dans `$(...)`, un
  # `exit` ne tuerait que le sous-shell et la suite continuerait en vert. C'est
  # l'appelant qui arrête, et chaque appel est donc suivi de `|| exit 2`.
  tree="$(cd "$1" && find . -mindepth 1 -printf '%y %m %p\n' | sort)"
  [ -n "$tree" ] || { printf 'HARNAIS arborescence vide pour %s : find -printf indisponible\n' "$1" >&2; return 2; }
  sums="$(cd "$1" && find . -mindepth 1 -type f -exec sha256sum {} + 2>/dev/null | sort)"
  printf '%s\n%s\n' "$tree" "$sums"
}

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
  # instructions_file attend un chemin, pas une chaîne quelconque. Le cas
  # nominal d'un dépôt qui n'a pas d'instructions propres est `disabled`.
  set_config "$1" instructions_file disabled
}

# Remplace la valeur d'une clé dans la configuration d'une cible.
set_config() {
  sed -i'' -e "s|^\([[:space:]]*\)$2:.*|\1$2: $3|" "$1/AGENTIC_RULES/project.config.yml"
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

printf 'instructions propres au dépôt\n'
# Le pointeur est le seul champ dont la valeur désigne un fichier. Un chemin
# faux est invisible sans contrôle : il ne casse rien jusqu'au jour où un agent
# cherche le document et ne le trouve pas.
set_config "$T" instructions_file disabled
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "disabled est accepté" "$rc" "0"

set_config "$T" instructions_file "DESIGN/INSTRUCTIONS.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un pointeur vers un fichier absent échoue" "$rc" "1"
printf '%s' "$out" | grep -q "POINTEUR MORT" && ok "le pointeur mort est nommé" || ko "le pointeur mort est nommé"
printf '%s' "$out" | grep -q "DESIGN/INSTRUCTIONS.md" && ok "le chemin fautif est cité" || ko "le chemin fautif est cité"

mkdir -p "$T/DESIGN" && printf 'instructions du projet\n' > "$T/DESIGN/INSTRUCTIONS.md"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "le même pointeur passe une fois le fichier créé" "$rc" "0"

# Le document désigné vit hors de AGENTIC_RULES/ : il ne doit pas être traité
# comme un ajout local, ni entrer dans le périmètre empreinté.
grep -q "DESIGN/INSTRUCTIONS.md" "$T/AGENTIC_RULES/.provenance" \
  && ko "le document désigné ne doit pas être empreinté" || ok "le document désigné reste hors empreinte"

# Un répertoire n'est pas un document : la règle dit un seul fichier. Le message
# doit dire pourquoi, pas prétendre que la cible n'existe pas.
rm "$T/DESIGN/INSTRUCTIONS.md"; mkdir -p "$T/DESIGN/INSTRUCTIONS.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un répertoire ne vaut pas document" "$rc" "1"
printf '%s' "$out" | grep -q "PAS UN FICHIER" && ok "le répertoire est diagnostiqué pour ce qu'il est" || ko "le répertoire est diagnostiqué pour ce qu'il est"
rmdir "$T/DESIGN/INSTRUCTIONS.md"; printf 'instructions du projet\n' > "$T/DESIGN/INSTRUCTIONS.md"

# Un lien cassé existe en tant que lien mais ne mène nulle part.
ln -s "n-existe-pas.md" "$T/DESIGN/casse.md"
set_config "$T" instructions_file "DESIGN/casse.md"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un lien cassé échoue" "$rc" "1"
printf '%s' "$out" | grep -q "LIEN CASSE" && ok "le lien cassé est diagnostiqué" || ko "le lien cassé est diagnostiqué"
rm "$T/DESIGN/casse.md"; set_config "$T" instructions_file "DESIGN/INSTRUCTIONS.md"

# Si readlink échoue, le contrôle doit refuser au lieu de conclure au hasard.
mkdir -p "$WORK/faux-outils"
printf '#!/bin/sh\nexit 1\n' > "$WORK/faux-outils/readlink"
chmod +x "$WORK/faux-outils/readlink"
ln -s "INSTRUCTIONS.md" "$T/DESIGN/lien-interne.md"
set_config "$T" instructions_file "DESIGN/lien-interne.md"
out="$(PATH="$WORK/faux-outils:$PATH" "$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un readlink en échec fait refuser" "$rc" "1"
printf '%s' "$out" | grep -q "CHEMIN IRRESOLU" && ok "l'échec de résolution est nommé" || ko "l'échec de résolution est nommé"
rm "$T/DESIGN/lien-interne.md"; set_config "$T" instructions_file "DESIGN/INSTRUCTIONS.md"

# Un chemin qui sort du dépôt ferait lire un fichier arbitraire du poste. Le
# cas dangereux est celui où la cible EXISTE : sans la garde, le contrôle passe
# et l'agent lit un fichier hors du dépôt en croyant lire les règles du projet.
printf 'contenu hors depot\n' > "$WORK/hors-depot.md"
set_config "$T" instructions_file "../hors-depot.md"
[ -f "$T/../hors-depot.md" ] && ok "la cible remontante existe vraiment" || ko "la cible remontante existe vraiment"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un chemin remontant vers un fichier existant échoue" "$rc" "1"
printf '%s' "$out" | grep -q "HORS DEPOT" && ok "le chemin remontant est nommé par sa destination" || ko "le chemin remontant est nommé par sa destination"
set_config "$T" instructions_file "/etc/passwd"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un chemin absolu échoue" "$rc" "1"
printf '%s' "$out" | grep -q "CHEMIN ABSOLU" && ok "le chemin absolu est nommé" || ko "le chemin absolu est nommé"

# Un filtre sur la chaîne ne dit rien de la destination. Un lien symbolique au
# nom anodin sort du dépôt sans contenir un seul `..` : c'est la forme
# réaliste de la fuite, celle qu'un relecteur humain ne voit pas dans un diff.
printf 'contenu hors depot par lien\n' > "$WORK/cible-du-lien.md"
ln -s "$WORK/cible-du-lien.md" "$T/DESIGN/lien.md"
set_config "$T" instructions_file "DESIGN/lien.md"
[ -f "$T/DESIGN/lien.md" ] && ok "le lien est vu comme un fichier existant" || ko "le lien est vu comme un fichier existant"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un lien symbolique vers l'extérieur échoue" "$rc" "1"
printf '%s' "$out" | grep -q "HORS DEPOT" && ok "la sortie du dépôt est nommée" || ko "la sortie du dépôt est nommée"
printf '%s' "$out" | grep -q "cible-du-lien.md" && ok "la destination réelle est citée" || ko "la destination réelle est citée"

# Un lien qui reste dans le dépôt est légitime et ne doit pas être refusé.
rm "$T/DESIGN/lien.md"
ln -s "INSTRUCTIONS.md" "$T/DESIGN/lien.md"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un lien symbolique interne reste conforme" "$rc" "0"
rm "$T/DESIGN/lien.md"

# Deux points dans un nom de fichier ne sont pas une remontée de chemin.
printf 'notes de version\n' > "$T/DESIGN/RELEASE-1.0..1.md"
set_config "$T" instructions_file "DESIGN/RELEASE-1.0..1.md"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un nom de fichier contenant deux points reste conforme" "$rc" "0"
set_config "$T" instructions_file "DESIGN/INSTRUCTIONS.md"

# Un `..` qui revient dans le dépôt n'en sort pas. Le contrôle jugeait sur la
# chaîne brute, avant toute résolution, et refusait un chemin strictement
# interne en affirmant une sortie qui n'avait pas lieu.
set_config "$T" instructions_file "DESIGN/../DESIGN/INSTRUCTIONS.md"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un .. qui revient dans le dépôt reste conforme" "$rc" "0"
set_config "$T" instructions_file "DESIGN/INSTRUCTIONS.md"

printf 'énumération du répertoire des règles\n'
# `find -printf` est une extension GNU. Le find de BSD la refuse, et le contrôle
# concluait alors à un ajout local au nom vide : un défaut d'outil présenté comme
# une dérive du dépôt. Le stub reproduit ce refus exactement.
REAL_FIND="$(command -v find)"
mkdir -p "$WORK/find-bsd"
{ printf '#!/bin/sh\n'
  printf 'for a in "$@"; do\n'
  printf '  [ "$a" = "-printf" ] || continue\n'
  printf '  echo "find: -printf: unknown primary or operator" >&2\n'
  printf '  exit 1\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$REAL_FIND"
} > "$WORK/find-bsd/find"
chmod +x "$WORK/find-bsd/find"
out="$(PATH="$WORK/find-bsd:$PATH" "$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un find sans -printf laisse le contrôle conforme" "$rc" "0"
printf '%s' "$out" | grep -q "AJOUT LOCAL" && ko "une dérive est inventée par le défaut d'outil" || ok "aucune dérive n'est inventée"

# Le contrôle doit rester utile sous ce find, pas seulement silencieux : un vrai
# ajout local passerait inaperçu si l'énumération portable ne voyait rien.
printf 'regle locale du depot\n' > "$T/AGENTIC_RULES/LOCAL_RULES.md"
out="$(PATH="$WORK/find-bsd:$PATH" "$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un find sans -printf détecte toujours un vrai ajout" "$rc" "1"
printf '%s' "$out" | grep -q "AJOUT LOCAL AGENTIC_RULES/LOCAL_RULES.md" \
  && ok "l'ajout est nommé sous le find dégradé" || ko "l'ajout est nommé sous le find dégradé"
rm "$T/AGENTIC_RULES/LOCAL_RULES.md"

# Une énumération qui ne rend rien est un défaut d'outil ou un corpus disparu.
# Le contrôle doit le dire, et surtout ne pas le traduire en constat de dérive.
mkdir -p "$WORK/find-muet"
printf '#!/bin/sh\nexit 0\n' > "$WORK/find-muet/find"
chmod +x "$WORK/find-muet/find"
out="$(PATH="$WORK/find-muet:$PATH" "$SCRIPT" check "$T" 2>&1)"; rc=$?
check "une énumération vide fait refuser" "$rc" "1"
printf '%s' "$out" | grep -q "ENUMERATION VIDE" \
  && ok "l'énumération vide est nommée pour ce qu'elle est" || ko "l'énumération vide est nommée pour ce qu'elle est"
printf '%s' "$out" | grep -q "AJOUT LOCAL" \
  && ko "une absence de données reste présentée comme une dérive" || ok "aucune dérive n'est déduite d'une absence de données"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "la cible reste conforme une fois le find rendu" "$rc" "0"

# Un nom de fichier peut contenir un saut de ligne. Découpée sur `\n`,
# l'énumération rendait deux noms au lieu d'un, tous deux au corpus, et le
# fichier passait : un contournement délibéré du contrôle, pas une maladresse.
# Le nom est fabriqué pour que ses deux moitiés soient l'une et l'autre
# autorisées, sans quoi le test passerait pour la mauvaise raison.
sournois="$T/AGENTIC_RULES/$(printf 'MAIN_RULES.md\nPROJECT_RULES.md')"
printf 'regle clandestine\n' > "$sournois"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "un nom contenant un saut de ligne fait refuser" "$rc" "1"
printf '%s' "$out" | grep -qF 'AJOUT LOCAL AGENTIC_RULES/MAIN_RULES.md\nPROJECT_RULES.md' \
  && ok "le nom clandestin est nommé d'un seul tenant" || ko "le nom clandestin est nommé d'un seul tenant"
# Compter les lignes, pas seulement en trouver une : un diagnostic scindé en
# deux signalerait le même fichier deux fois sous deux noms qui n'existent pas.
n="$(printf '%s' "$out" | grep -c 'AJOUT LOCAL')"
check "le nom vaut un seul ajout, pas deux" "$n" "1"
rm "$sournois"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "la cible redevient conforme une fois le nom retiré" "$rc" "0"

# Les autres caractères de contrôle cassent l'affichage sans cacher le fichier.
# La détection ne dépend pas d'eux, la lisibilité du diagnostic si.
sournois="$T/AGENTIC_RULES/$(printf 'REGLE\tLOCALE.md')"
printf 'regle clandestine\n' > "$sournois"
out="$("$SCRIPT" check "$T" 2>&1)"; rc=$?
check "une tabulation dans le nom fait refuser" "$rc" "1"
printf '%s' "$out" | grep -qF 'AJOUT LOCAL AGENTIC_RULES/REGLE\tLOCALE.md' \
  && ok "la tabulation est rendue visible" || ko "la tabulation est rendue visible"
rm "$sournois"

# La lecture doit tenir compte de la section. Le schéma réutilise déjà `server`
# sous memory.live et sous memory.graph ; une lecture par nom terminal rendrait
# la valeur de la mauvaise section, en silence. Un leurre placé AVANT la section
# project le démontre : une lecture aveugle prendrait son chemin, qui est mort.
# Deux leurres, un de chaque côté de la vraie clé. Un seul ne prouverait rien :
# placé avant, la règle « dernière occurrence gagne » retombe sur la bonne
# valeur par coïncidence, et une lecture aveugle à la section passerait le test.
cp "$T/AGENTIC_RULES/project.config.yml" "$WORK/cfg.bak"
{ printf 'leurre_avant:\n  instructions_file: DESIGN/AVANT-N-EXISTE-PAS.md\n\n'
  cat "$T/AGENTIC_RULES/project.config.yml"
  printf '\nleurre_apres:\n  instructions_file: DESIGN/APRES-N-EXISTE-PAS.md\n'
} > "$WORK/cfg.tmp"
mv "$WORK/cfg.tmp" "$T/AGENTIC_RULES/project.config.yml"
check "trois clés homonymes coexistent" "$(grep -c 'instructions_file' "$T/AGENTIC_RULES/project.config.yml")" "3"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "les clés homonymes hors section sont ignorées des deux côtés" "$rc" "0"
cp "$WORK/cfg.bak" "$T/AGENTIC_RULES/project.config.yml"

# Clé dupliquée dans la MÊME section : les lecteurs YAML gardent la dernière.
# Une configuration pareille est malformée, mais le contrôle ne doit pas se
# fonder sur une valeur que personne d'autre ne lirait.
cp "$T/AGENTIC_RULES/project.config.yml" "$WORK/cfg.bak2"
sed -i'' -e 's|^\([[:space:]]*\)instructions_file: DESIGN/INSTRUCTIONS.md|\1instructions_file: DESIGN/N-EXISTE-PAS.md\n\1instructions_file: DESIGN/INSTRUCTIONS.md|' \
  "$T/AGENTIC_RULES/project.config.yml"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "une clé dupliquée retient la dernière valeur" "$rc" "0"
cp "$WORK/cfg.bak2" "$T/AGENTIC_RULES/project.config.yml"

# Une configuration en schéma 1 n'a pas la clé. Son absence ne bloque rien,
# sinon la montée de version casserait les dépôts déjà installés.
grep -v '^  instructions_file:' "$T/AGENTIC_RULES/project.config.yml" > "$T/AGENTIC_RULES/cfg.tmp"
mv "$T/AGENTIC_RULES/cfg.tmp" "$T/AGENTIC_RULES/project.config.yml"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "une configuration sans la clé reste conforme" "$rc" "0"

# Le TO_FILL doit continuer de bloquer, sinon la clé serait oubliable en silence.
printf '  instructions_file: TO_FILL\n' >> "$T/AGENTIC_RULES/project.config.yml"
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "un TO_FILL sur la clé échoue" "$rc" "1"
"$SCRIPT" update "$T" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
grep -v '^  instructions_file: TO_FILL' "$T/AGENTIC_RULES/project.config.yml" > "$T/AGENTIC_RULES/cfg.tmp"
mv "$T/AGENTIC_RULES/cfg.tmp" "$T/AGENTIC_RULES/project.config.yml"
set_config "$T" instructions_file disabled
"$SCRIPT" check "$T" >/dev/null 2>&1; rc=$?
check "retour à un état conforme" "$rc" "0"

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
before_snap="$(snapshot "$T2")" || exit 2
"$SCRIPT" install "$T2" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "install refuse d'écraser un fichier existant" "$rc" "1"
after_snap="$(snapshot "$T2")" || exit 2
[ "$after_snap" = "$before_snap" ] && ok "le refus laisse la cible strictement inchangée" || ko "le refus laisse la cible strictement inchangée"
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

printf 'comparaison à la source\n'
T5="$WORK/depot cinq"; mkdir -p "$T5"
"$SCRIPT" install "$T5" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
fill_values "$T5"
"$SCRIPT" check "$T5" --remote --source "$SRC" >/dev/null 2>&1; rc=$?
check "check --remote réussit sur une copie fidèle" "$rc" "0"
# Falsification cohérente : le fichier et son empreinte sont modifiés ensemble.
printf '\nregle glissee en douce\n' >> "$T5/AGENTIC_RULES/MAIN_RULES.md"
newh="$(sha256sum "$T5/AGENTIC_RULES/MAIN_RULES.md" | cut -d' ' -f1)"
sed -i'' -e "s|^sha256 AGENTIC_RULES/MAIN_RULES.md .*|sha256 AGENTIC_RULES/MAIN_RULES.md $newh|" "$T5/AGENTIC_RULES/.provenance"
"$SCRIPT" check "$T5" >/dev/null 2>&1; rc=$?
check "le contrôle local ne voit pas une falsification cohérente" "$rc" "0"
out="$("$SCRIPT" check "$T5" --remote --source "$SRC" 2>&1)"; rc=$?
check "la comparaison à la source la voit" "$rc" "1"
printf '%s' "$out" | grep -q "DIFFERENT DE LA SOURCE" && ok "la falsification est nommée" || ko "la falsification est nommée"
"$SCRIPT" update "$T5" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
"$SCRIPT" check "$T5" --remote --source "$WORK/source absente" >/dev/null 2>&1; rc=$?
check "une source injoignable fait échouer --remote" "$rc" "1"

printf 'MANIFEST hostile\n'
printf 'a ne pas supprimer\n' > "$WORK/temoin externe.txt"
printf '../temoin externe.txt\n' >> "$T5/AGENTIC_RULES/MANIFEST"
before_snap="$(snapshot "$T5")" || exit 2
out="$("$SCRIPT" update "$T5" --ref v0.0.0-test --source "$SRC" 2>&1)"; rc=$?
check "un chemin remontant fait échouer la mise à jour" "$rc" "1"
printf '%s' "$out" | grep -q "chemin remontant interdit" && ok "l'échec est bien celui du chemin remontant" || ko "l'échec est bien celui du chemin remontant"
[ -f "$WORK/temoin externe.txt" ] && ok "le fichier hors cible survit" || ko "le fichier hors cible survit"
after_snap="$(snapshot "$T5")" || exit 2
[ "$after_snap" = "$before_snap" ] && ok "la cible reste strictement inchangée" || ko "la cible reste strictement inchangée"

printf 'retour arrière\n'
T6="$WORK/depot six"; mkdir -p "$T6"
"$SCRIPT" install "$T6" --ref v0.0.0-test --source "$SRC" >/dev/null 2>&1
fill_values "$T6"
# Dernier fichier de la charge utile rendu inremplaçable : la bascule échoue
# après avoir déjà déplacé les précédents.
rm "$T6/AGENTIC_RULES/project.config.example.yml"
mkdir -p "$T6/AGENTIC_RULES/project.config.example.yml/occupe"
printf 'x\n' > "$T6/AGENTIC_RULES/project.config.example.yml/occupe/x"
before_snap="$(snapshot "$T6")" || exit 2
"$SCRIPT" update "$T6" --ref v0.0.1-test --source "$SRC" >/dev/null 2>&1; rc=$?
check "une bascule impossible échoue" "$rc" "1"
after_snap="$(snapshot "$T6")" || exit 2
[ "$after_snap" = "$before_snap" ] \
  && ok "la cible est rendue strictement intacte, contenus, types et modes" \
  || ko "la cible est rendue strictement intacte, contenus, types et modes"
grep -q "ligne ajoutee en v0.0.1" "$T6/AGENTIC_RULES/REVIEWERS.md" \
  && ko "aucun fichier ne porte la version échouée" || ok "aucun fichier ne porte la version échouée"

# Parent impossible : AGENTIC_RULES occupe par un fichier. L echec survient sur
# le quatrieme fichier de la charge utile, les trois premiers sont deja poses.
T7="$WORK/depot sept"; mkdir -p "$T7"
printf 'ce n est pas un repertoire\n' > "$T7/AGENTIC_RULES"
before_snap="$(snapshot "$T7")" || exit 2
out="$("$SCRIPT" install "$T7" --ref v0.0.0-test --source "$SRC" 2>&1)"; rc=$?
check "un parent impossible fait échouer l'installation" "$rc" "1"
printf '%s' "$out" | grep -q "répertoire parent impossible" && ok "l'échec est bien celui du parent" || ko "l'échec est bien celui du parent"
[ -e "$T7/AGENTS.md" ] && ko "les fichiers déjà posés sont retirés" || ok "les fichiers déjà posés sont retirés"
after_snap="$(snapshot "$T7")" || exit 2
[ "$after_snap" = "$before_snap" ] && ok "un parent impossible ne laisse pas de corpus hybride" || ko "un parent impossible ne laisse pas de corpus hybride"

# Le contrôle du dépôt source n'était exercé par aucun test. C'est pourtant lui
# qui décide de ce qui part en distribution : un fichier parasite qu'il laisse
# passer est empreinté au tag suivant, puis propagé dans toute la flotte. Il
# portait le même défaut que le script distribué, en pire, parce que rien en
# aval ne le rattrape.
#
# La copie se construit depuis le MANIFEST, fichier par fichier, et non par un
# `cp -R` du répertoire. Recopier l'arbre y ferait entrer ce qui y traîne, et
# `check-source.sh` refuse par construction tout fichier étranger : un
# `.DS_Store` posé par le Finder faisait alors tomber deux assertions qui ne
# parlent pas de lui. L'ironie compte ici, cette PR porte sur macOS. Un
# instantané git réglerait aussi le problème, mais la suite exerce l'arbre de
# travail, et c'est ce qui permet de valider un correctif avant de le commiter.
SRC="$WORK/copie de la source"; mkdir -p "$SRC/AGENTIC_RULES" "$SRC/scripts"
while IFS= read -r f; do
  mkdir -p "$SRC/$(dirname "$f")"
  cp -p "$ROOT/$f" "$SRC/$f"
done <<< "$(grep -v '^[[:space:]]*#' "$ROOT/AGENTIC_RULES/MANIFEST" | grep -v '^[[:space:]]*$')"
cp -p "$ROOT/AGENTIC_RULES/project.config.yml" "$SRC/AGENTIC_RULES/"
cp -p "$ROOT/scripts/check-source.sh" "$SRC/scripts/"
"$SRC/scripts/check-source.sh" >/dev/null 2>&1; rc=$?
check "la copie du dépôt source est conforme" "$rc" "0"

# Le nom est fabriqué sur deux contraintes. Ses deux moitiés doivent être l'une
# et l'autre autorisées, sinon le test passerait pour la mauvaise raison. Et il
# ne doit pas finir en `.md`, sans quoi le glob du premier contrôle l'attrape
# par accident, en nommant au passage un fichier qui n'existe pas.
clandestin="$SRC/AGENTIC_RULES/$(printf '.provenance\nproject.config.yml')"
printf 'charge clandestine\n' > "$clandestin"
out="$("$SRC/scripts/check-source.sh" 2>&1)"; rc=$?
check "un nom à saut de ligne fait refuser la source" "$rc" "1"
printf '%s' "$out" | grep -qF 'fichier parasite dans AGENTIC_RULES/ : .provenance\nproject.config.yml' \
  && ok "le parasite de la source est nommé d'un seul tenant" || ko "le parasite de la source est nommé d'un seul tenant"
rm "$clandestin"
"$SRC/scripts/check-source.sh" >/dev/null 2>&1; rc=$?
check "la source redevient conforme une fois le nom retiré" "$rc" "0"

# Construire la copie depuis le MANIFEST rend un cas structurellement absent :
# un fichier présent sur disque mais non manifesté, c'est à dire la règle
# ajoutée sans sa ligne au MANIFEST, l'oubli le plus probable de ce dépôt. Le
# cas s'injecte donc après coup, en retirant la ligne du MANIFEST copié plutôt
# qu'en comptant sur ce qui traînerait sur le disque. Ces assertions couvrent un
# contrôle qui n'en avait aucun ; elles ne tombent pas contre la version
# précédente, qui le détectait déjà.
#
# Les deux contrôles lisent le même MANIFEST, donc retirer une ligne les fait
# tous deux réagir : le refus global est satisfait par l'un ou l'autre et ne
# prouve rien à lui seul. C'est la vérification du message qui épingle celui-ci,
# et elle seule tombe quand on neutralise la boucle. Le dire plutôt que compter
# deux couvertures là où il n'y en a qu'une.
grep -v '^AGENTIC_RULES/REVIEWERS\.md$' "$SRC/AGENTIC_RULES/MANIFEST" > "$SRC/manifeste ampute"
mv "$SRC/manifeste ampute" "$SRC/AGENTIC_RULES/MANIFEST"
out="$("$SRC/scripts/check-source.sh" 2>&1)"; rc=$?
check "une règle absente du MANIFEST fait refuser la source" "$rc" "1"
printf '%s' "$out" | grep -q 'fichier du corpus absent du MANIFEST : AGENTIC_RULES/REVIEWERS.md' \
  && ok "la règle non manifestée est nommée" || ko "la règle non manifestée est nommée"
cp -p "$ROOT/AGENTIC_RULES/MANIFEST" "$SRC/AGENTIC_RULES/MANIFEST"
"$SRC/scripts/check-source.sh" >/dev/null 2>&1; rc=$?
check "la source redevient conforme une fois le MANIFEST rétabli" "$rc" "0"

# Le couplage décrit juste au-dessus se défait sur une entrée hors du répertoire
# des règles. La boucle des parasites ne parcourt que `AGENTIC_RULES/`, tandis
# que celle du MANIFEST couvre aussi les pointeurs de la racine. Amputer
# `CLAUDE.md` ne laisse donc qu'un seul contrôle réagir, et le refus devient
# imputable à lui seul. Les deux entrées gardent chacune leur raison d'être :
# `REVIEWERS.md` exerce la branche glob, celle du scénario réel d'une règle
# ajoutée sans sa ligne ; `CLAUDE.md` prouve que ce contrôle refuse tout seul.
grep -v '^CLAUDE\.md$' "$SRC/AGENTIC_RULES/MANIFEST" > "$SRC/manifeste ampute"
mv "$SRC/manifeste ampute" "$SRC/AGENTIC_RULES/MANIFEST"
out="$("$SRC/scripts/check-source.sh" 2>&1)"; rc=$?
check "un pointeur de racine non manifesté fait refuser à lui seul" "$rc" "1"
printf '%s' "$out" | grep -q 'fichier du corpus absent du MANIFEST : CLAUDE.md' \
  && ok "le pointeur non manifesté est nommé" || ko "le pointeur non manifesté est nommé"
n="$(printf '%s' "$out" | grep -c 'fichier parasite' || true)"
check "aucun autre contrôle ne réagit sur cette entrée" "$n" "0"
cp -p "$ROOT/AGENTIC_RULES/MANIFEST" "$SRC/AGENTIC_RULES/MANIFEST"
"$SRC/scripts/check-source.sh" >/dev/null 2>&1; rc=$?
check "la source redevient conforme après la seconde amputation" "$rc" "0"

# Un parasite ordinaire reste détecté : la correction ne doit pas avoir déplacé
# la détection au lieu de l'élargir.
printf 'regle locale\n' > "$SRC/AGENTIC_RULES/LOCAL_RULES.md"
out="$("$SRC/scripts/check-source.sh" 2>&1)"; rc=$?
check "un parasite ordinaire fait toujours refuser la source" "$rc" "1"
printf '%s' "$out" | grep -q 'LOCAL_RULES.md' \
  && ok "le parasite ordinaire est nommé" || ko "le parasite ordinaire est nommé"
rm "$SRC/AGENTIC_RULES/LOCAL_RULES.md"

printf '\n%d succès, %d échec(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
