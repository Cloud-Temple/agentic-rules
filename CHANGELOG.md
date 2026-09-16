# Changelog

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
versionnement sémantique.

## [1.3.0] - 2026-09-16

### Modifié

- `PROJECT_RULES.md` : nouvelle section « Trouver l'espace du projet ».
  L'espace est cherché sur tous les serveurs Live Memory de la session, pas
  seulement sur celui que `memory.live.server` déclare. Trouvé sur plusieurs,
  l'utilisateur choisit ; sur un seul, l'agent le retient sans demander ; sur
  aucun, la création bornée existante s'applique. Le serveur retenu devient le
  serveur effectif que cible toute la session, et l'agent corrige
  `memory.live.server` s'il diffère.
- `PROJECT_RULES.md` : les renvois au serveur déclaré visent désormais le serveur
  effectif, dans la table des espaces, le ciblage des appels, l'étape 1 du
  démarrage et la section « Mémoire absente ou en panne ».
- `MAIN_RULES.md` : la section d'autonomie distingue autoriser une action et
  désigner son objet. Le merge reste le seul point d'autorisation humaine. Le
  choix entre deux espaces homonymes est une désignation, nommée comme seule
  exception au principe « continuer le travail indépendant de la réponse »,
  parce qu'aucun travail n'est indépendant de la mémoire qui sera chargée.
- `PROJECT_RULES.md` : un refus d'accès rencontré pendant la recherche n'est pas
  une absence. Tant qu'il n'est pas élucidé, ne rien créer. Sans cette clause,
  un serveur qui refuse au lieu de répondre « absent » ramenait le doublon vide.
- `PROJECT_RULES.md` : un identifiant trouvé sur un seul serveur mais dont la
  description ou le propriétaire désigne un autre projet est une collision, pas
  l'espace cherché. L'agent arrête, avec la portée d'un blocage mémoire mais sans
  son remède : ne rien créer, ne pas relancer la recherche, ne pas demander
  l'ouverture d'un accès à l'espace d'un tiers. Seule une personne peut corriger
  `memory.live.space_id`. Quand description et propriétaire sont tous deux vides,
  l'espace est retenu, mais l'agent dit qu'il n'a rien pu lire plutôt que de
  laisser croire à une vérification concluante.
- `MAIN_RULES.md` : la collision d'identifiant rejoint les causes d'arrêt
  obligatoire du prérequis mémoire, qui se lisaient comme une liste fermée.
- `PROJECT_RULES.md` : la correction de `memory.live.server` désigne où vivent les
  données persistées du projet. Elle relève de la dernière ligne du tableau de
  risque de `WORKFLOW_ENGINEERING.md` et passe par une PR dédiée, jamais par un
  commit direct ni mêlée à la branche d'une autre tâche.
- `project.config.example.yml` : le commentaire de `memory.live.server` dit ce
  que la clé désigne réellement, la cible de création et non le seul serveur
  consulté.

### Pourquoi

Un dépôt peut déclarer un espace qui vit sur l'autre serveur. La règle
précédente interdisait de regarder ailleurs, puis prescrivait la création : elle
produisait un doublon vide pendant que la mémoire réelle restait sur le serveur
non consulté, sans qu'aucune erreur ne le signale. Le cas est réel dans la
flotte.

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

Un fichier réservé dans `AGENTIC_RULES/` aurait demandé une seconde exception
dans le répertoire dont la promesse est d'être identique partout, et obligé
chaque dépôt à déplacer son savoir. Le pointeur réutilise le seul canal de
variation existant et laisse chaque document là où le projet le range.

### Confinement

Le chemin désigne un fichier du dépôt. Un chemin absolu, une remontée hors de la
racine, ou un lien symbolique dont la cible sort du dépôt sont refusés. Cette
règle vaut des deux côtés : le contrôle de conformité la vérifie, et
`MAIN_RULES.md` la donne à l'agent, qui n'exécute jamais ce contrôle. Un
pointeur non vérifiable ne s'ouvre pas.

Le détail des quatre passes de revue qui ont mené à cette forme est dans la
PR #7, pas ici.

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
