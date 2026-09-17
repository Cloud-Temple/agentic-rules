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

for f in AGENTS.md CLAUDE.md QWEN.md $(ls AGENTIC_RULES/*.md 2>/dev/null); do
  printf '%s\n' "$manifest" | grep -qx "$f" || { printf 'fichier du corpus absent du MANIFEST : %s\n' "$f"; rc=1; }
done

# Rien d'autre que la charge utile, la configuration locale et la provenance.
allowed="$(printf '%s\n' "$manifest" | sed -n 's|^AGENTIC_RULES/||p')"$'\n'"project.config.yml"$'\n'".provenance"
while IFS= read -r base; do
  printf '%s\n' "$allowed" | grep -qx "$base" \
    || { printf 'fichier parasite dans AGENTIC_RULES/ : %s\n' "$base"; rc=1; }
done < <(cd AGENTIC_RULES && find . -mindepth 1 | sed 's|^\./||' | sort)

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
