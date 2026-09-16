# Changelog

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
versionnement sémantique.

## [1.2.0] - 2026-09-16

### Ajouté

- `project.config.yml` : clé `project.instructions_file`. Elle désigne un
  document du dépôt que l'agent lit au démarrage, après `PROJECT_RULES.md`.
  Un dépôt peut enfin porter du savoir qui ne vaut que pour lui sans sortir du
  corpus, et sans qu'une mise à jour l'écrase.
- `MAIN_RULES.md` : une ligne d'index pour ce document, et une section qui borne
  ce qu'il a le droit de contenir.
- `agentic-rules.sh` : le contrôle de conformité échoue si ce champ porte un
  chemin absolu, un chemin qui remonte hors du dépôt, ou un chemin vers un
  fichier qui n'existe pas.

### Modifié

- Le schéma de configuration passe en version 2, et `MAIN_RULES.md` dit
  enfin à quoi sert ce numéro. Un champ que la génération déclarée connaissait
  mais qui a disparu du fichier reste un champ non traité, donc bloquant. Un
  champ introduit plus tard est simplement absent et vaut `disabled`. Les huit
  dépôts déjà installés restent donc conformes sans être touchés.
- `config_value` lit une clé par son chemin complet, `project.instructions_file`
  et non `instructions_file`. Le schéma réutilise `server` sous `memory.live` et
  sous `memory.graph` : une lecture par nom terminal rendait la valeur de la
  mauvaise section, en silence.

### Pourquoi un pointeur plutôt qu'un fichier réservé

La première piste était un `AGENTIC_RULES/PROJECT_NOTES.md` hors charge utile.
Elle demandait une deuxième exception dans le répertoire dont la promesse entière
est « identique à l'octet près partout », obligeait chaque dépôt à déplacer son
savoir dans un fichier neuf, et produisait un fichier qui ressemble à du corpus
sans en être. Le pointeur réutilise le seul canal de variation qui existe déjà,
et laisse chaque document là où le projet le range.

### Ce que la revue a corrigé

La première rédaction filtrait le chemin sur sa seule forme : `/*` pour
l'absolu, `*..*` pour la remontée. Deux défauts, tous deux reproduits.

Un lien symbolique au nom anodin sort du dépôt sans contenir un seul `..`, et
le contrôle rendait `conforme` : l'agent lisait un fichier arbitraire du poste
en croyant lire les instructions du projet. Le contrôle résout maintenant le
chemin réel, liens compris, et vérifie qu'il reste sous la racine.

À l'inverse, `*..*` refusait un nom de fichier légitime comme
`RELEASE-1.0..1.md`. Le motif n'encadre plus que le segment `..`, comme le fait
déjà `read_manifest` dans le même script.

Une seconde passe a trouvé que le message d'échec mentait sur ce qu'il avait
rencontré : un répertoire ou un lien cassé étaient annoncés comme « n'existe
pas ». Le verdict était bon, le diagnostic faux. Trois messages distincts
maintenant. Elle a aussi trouvé qu'un échec de `readlink` n'était exercé par
aucun test, et qu'une clé dupliquée dans une même section retenait la première
valeur là où tout lecteur YAML garde la dernière. Les deux sont corrigés et
couverts.

Le plafond anti-boucle de `resolve_path` reste sans test, et c'est écrit dans le
code : le seul appelant vérifie `-f` avant d'appeler, or le noyau rend déjà
ELOOP au-delà de sa propre limite. Forcer cet état dans un test serait du
théâtre. Le plafond reste pour le jour où la fonction servira ailleurs.

### Ce que le pointeur ne doit pas devenir

Le document désigné décrit le projet, jamais la méthode. Il ne définit ni règle
mémoire, ni workflow Git, ni politique de revue, ni point d'autorisation humaine.
En cas de contradiction avec le corpus, le corpus l'emporte et l'agent signale le
conflit. Un seul fichier, pas un répertoire, pour qu'il ne devienne pas l'index
d'un second corpus local.

## [1.1.0] - 2026-09-16

### Ajouté

- `PROJECT_RULES.md` : section « Espace mémoire absent ». Un dépôt qu'on vient
  de mettre en conformité déclare un `space_id` qui n'existe pas encore. Les
  règles n'avaient pas ce cas et le traitaient comme une panne, donc un arrêt
  du travail, alors qu'il suffisait de créer l'espace. L'agent tente désormais
  `space_create` une fois, avec l'identifiant exact de la configuration.

### Modifié

- `PROJECT_RULES.md` : « Mémoire absente ou en panne » interdisait toute
  recréation après un refus d'accès. Cette interdiction visait le contournement
  d'un refus, mais elle bloquait aussi le premier démarrage légitime. Elle
  autorise maintenant la tentative unique décrite dans la nouvelle section, et
  continue d'interdire le changement d'espace, l'élargissement des droits et
  les réessais en boucle.

### Pourquoi la création est sûre

Le serveur rend le même refus d'accès pour un espace absent et pour un espace
existant hors des droits du jeton. La lecture seule ne tranche pas, alors que
`space_create` sur un espace existant rend `already_exists` sans rien écraser :
la tentative sert de test autant que de remède.

Le statut seul ne conclut pas. Sur un espace existant, le serveur répare l'accès
du jeton qui l'a créé et l'annonce dans `creator_access_repair`, donc un
`already_exists` peut être un démarrage normal. Une création peut à l'inverse
porter `creator_access_pending` quand le droit n'a pas pu être écrit, et le
serveur demande alors de rejouer le même appel. La règle impose de lire ces
champs et borne l'ensemble à deux appels. Une réponse inclassable conduit à
l'arrêt, et c'est la lecture suivie de la note de cadrage qui prouve l'accès.

Les `rules` restent vides pour que le serveur applique sa structure par défaut :
elles sont immuables après création. Un serveur sans modèle par défaut refuse
l'appel, ce qui signale un défaut de configuration, pas un espace manquant.

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
- `scripts/test/run.sh`, cinquante-quatre assertions hors réseau sur le script,
  dont le retour arrière d'une bascule échouée, le refus d'un MANIFEST portant
  un chemin remontant, et la falsification cohérente que seul `--remote` voit.
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
