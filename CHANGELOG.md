# Changelog

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
versionnement sémantique.

## [1.0.0] - 2026-09-15

Première version du corpus dans son dépôt dédié.

### Filiation

Le corpus vivait auparavant dans `Cloud-Temple/starter-kit`, sous
`boilerplate/AGENTIC_RULES/`, jusqu'à la version `v2.0.4` du starter-kit. Il
n'y était pas distribué : les dépôts créés depuis le boilerplate ne recevaient
pas les règles, le répertoire d'installation étant ignoré par Git. Ce dépôt
existe pour que la source soit unique, versionnée pour elle-même et réellement
distribuée. La numérotation repart à `1.0.0` ; l'historique antérieur reste
lisible dans le starter-kit.

### Ajouté

- Les cinq fichiers de règles transposés depuis le starter-kit `v2.0.4`.
- `AGENTIC_RULES/REVIEWERS.md`, un modèle de relecture par fournisseur.
  Anthropic `claude-sonnet-5`, OpenAI `gpt-5.6-terra`, LLMaaS `qwen3.8:27b`.
  Aucun niveau de raisonnement ni tier, pour que la revue soit reproductible.
- `AGENTIC_RULES/project.config.example.yml`, seul fichier variable d'un dépôt
  à l'autre, avec ses trois états, valeur, `disabled` et `TO_FILL`.
- Les fichiers d'amorçage `AGENTS.md`, `CLAUDE.md` et `QWEN.md`, distribués
  avec le corpus pour qu'un dépôt soit couvert quel que soit l'outil agentique.
- `AGENTIC_RULES/agentic-rules.sh`, installation, mise à jour et contrôle de
  conformité par empreinte, vendoré avec le corpus pour que le contrôle se fasse
  sans accès sortant. `AGENTIC_RULES/.provenance` nomme le tag, le commit et le
  hachage de chaque fichier distribué. L'installation prépare tout dans un
  répertoire d'attente avant bascule et refuse d'écraser un fichier existant.
- `AGENTIC_RULES/MANIFEST`, la liste de la charge utile, distribuée avec elle.
- `scripts/test/run.sh`, trente-neuf assertions hors réseau sur le script.
- `scripts/check-source.sh`, qui refuse un fichier de règles absent du MANIFEST
  ou un fichier parasite dans `AGENTIC_RULES/`.
- `templates/workflows/agentic-conformity.yml`, le job de CI à copier dans
  chaque dépôt consommateur.

### Modifié depuis le starter-kit v2.0.4

- La langue n'est plus imposée au français. L'agent écrit dans la langue
  publique déclarée par le projet, ou à défaut dans celle de l'utilisateur.
  `MAIN_RULES.md` et `WORKFLOW_GIT.md` disaient l'inverse l'un de l'autre.
- Les identifiants mémoire ne sont plus des marqueurs à remplacer dans le texte
  des règles. Ils sont lus dans la configuration du projet, ce qui rend le
  corpus identique partout.
- Graph Memory ne se retire plus en supprimant sa section des règles. Il se
  désactive par configuration, pour la même raison.
- La revue indépendante renvoie à `REVIEWERS.md` au lieu de laisser le choix
  du modèle implicite.
