#!/usr/bin/env bash
# Contrôles propres au dépôt source du corpus.
#
# Le dépôt source n'a pas de copie vendorée à comparer : sa racine est la
# référence. Ce script garde ce qui casserait réellement la distribution, un
# fichier de règles oublié au MANIFEST, un MANIFEST qui annonce un fichier
# absent, un fichier parasite dans AGENTIC_RULES/, puis vérifie que le dépôt
# applique sa propre configuration.
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0

manifest="$(grep -v '^[[:space:]]*#' AGENTIC_RULES/MANIFEST | grep -v '^[[:space:]]*$')"

while IFS= read -r f; do
  [ -f "$f" ] || { printf 'MANIFEST annonce un fichier absent : %s\n' "$f"; rc=1; }
done <<< "$manifest"

# Le MANIFEST se lit ligne par ligne : un nom contenant un saut de ligne y est
# irreprésentable, ses lignes sont donc sûres. Ce qui vient du disque ne l'est
# pas, et c'est de ce côté que tout le soin porte.
declare -a entries=()
while IFS= read -r f; do
  entries+=("$f")
done <<< "$manifest"

# L'appartenance se teste par égalité de chaînes. `grep -x` traiterait un motif
# contenant un saut de ligne comme plusieurs motifs alternatifs, et un nom
# fabriqué pour que ses moitiés soient autorisées passerait sans rien déclencher.
has_entry() {
  local needle="$1" e
  for e in "${entries[@]}"; do
    if [ "$e" = "$needle" ]; then return 0; fi
  done
  return 1
}

# Le glob rend chaque nom d'un bloc. `$(ls ...)` découpait sur les espaces et
# les sauts de ligne : un fichier nommé avec un saut de ligne s'y scindait en
# deux, et le diagnostic nommait un fichier qui n'existe pas.
shopt -s nullglob
for f in AGENTS.md CLAUDE.md QWEN.md AGENTIC_RULES/*.md; do
  has_entry "$f" || { printf 'fichier du corpus absent du MANIFEST : %s\n' "$f"; rc=1; }
done
shopt -u nullglob

# Rien d'autre que la charge utile, la configuration locale et la provenance.
declare -a allowed=("project.config.yml" ".provenance")
while IFS= read -r f; do
  case "$f" in AGENTIC_RULES/*) allowed+=("${f#AGENTIC_RULES/}") ;; esac
done <<< "$manifest"

# Même défaut que dans le script distribué, corrigé de la même façon. Découpée
# sur `\n`, l'énumération rendait deux noms autorisés pour un seul fichier :
# `.provenance<LF>project.config.yml` traversait ce contrôle sans rien
# déclencher, et c'est ici que se décide ce qui part en distribution.
seen=0
while IFS= read -r -d '' base; do
  seen=$((seen + 1))
  base="${base#./}"
  found=0
  for a in "${allowed[@]}"; do
    if [ "$a" = "$base" ]; then found=1; break; fi
  done
  if [ "$found" -eq 0 ]; then
    # Rendre les caractères de contrôle visibles, sinon le message s'étale sur
    # plusieurs lignes et redevient indéchiffrable.
    shown="$base"
    shown="${shown//$'\r'/\\r}"
    shown="${shown//$'\n'/\\n}"
    shown="${shown//$'\t'/\\t}"
    printf 'fichier parasite dans AGENTIC_RULES/ : %s\n' "$shown"
    rc=1
  fi
done < <(cd AGENTIC_RULES && find . -mindepth 1 -print0)
[ "$seen" -gt 0 ] || { printf 'enumeration vide de AGENTIC_RULES/ : find inutilisable\n'; rc=1; }

[ -x AGENTIC_RULES/agentic-rules.sh ] || { printf 'le script distribué n est pas exécutable\n'; rc=1; }

if [ -f AGENTIC_RULES/project.config.yml ]; then
  sed -e 's/[[:space:]]#.*$//' -e 's/^[[:space:]]*#.*$//' AGENTIC_RULES/project.config.yml \
    | grep -q 'TO_FILL' \
    && { printf 'le dépôt source laisse des TO_FILL dans sa propre configuration\n'; rc=1; }
else
  printf 'configuration du dépôt source absente : AGENTIC_RULES/project.config.yml\n'; rc=1
fi

[ "$rc" -eq 0 ] && printf 'source conforme\n' || printf 'source non conforme\n'
exit "$rc"
