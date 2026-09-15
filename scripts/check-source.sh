#!/usr/bin/env bash
# Contrôles propres au dépôt source du corpus.
#
# Le dépôt source n'a pas de copie vendorée à comparer : sa racine est la
# référence. Ce script garde ce qui peut réellement casser la distribution,
# un fichier de règles oublié au MANIFEST ou un MANIFEST qui annonce un
# fichier absent, puis vérifie que le dépôt applique sa propre configuration.
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0

manifest="$(grep -v '^[[:space:]]*#' MANIFEST | grep -v '^[[:space:]]*$')"

while IFS= read -r f; do
  [ -f "$f" ] || { printf 'MANIFEST annonce un fichier absent : %s\n' "$f"; rc=1; }
done <<< "$manifest"

for f in AGENTS.md CLAUDE.md QWEN.md $(ls AGENTIC_RULES/*.md 2>/dev/null) AGENTIC_RULES/project.config.example.yml; do
  printf '%s\n' "$manifest" | grep -qx "$f" || { printf 'fichier du corpus absent du MANIFEST : %s\n' "$f"; rc=1; }
done

if [ -f AGENTIC_RULES/project.config.yml ]; then
  grep -q 'TO_FILL' AGENTIC_RULES/project.config.yml \
    && { printf 'le dépôt source laisse des TO_FILL dans sa propre configuration\n'; rc=1; }
else
  printf 'configuration du dépôt source absente : AGENTIC_RULES/project.config.yml\n'; rc=1
fi

[ "$rc" -eq 0 ] && printf 'source conforme\n' || printf 'source non conforme\n'
exit "$rc"
