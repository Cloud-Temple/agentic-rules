# Corpus de règles agentiques Cloud Temple

Les règles de travail que suivent les agents sur les dépôts Cloud Temple :
contrat de travail, mémoire Hivemind obligatoire (SHORT/MID/LONG), discipline d'ingénierie,
workflow Git et GitHub, pilotage par EPIC et Project, relecteur indépendant.

Ce dépôt est la source unique. Les autres dépôts en prennent une copie vendorée,
identique à l'octet près, et un job de CI vérifie qu'elle n'a pas dérivé.

## Ce que contient le corpus

| Fichier | Rôle |
| --- | --- |
| `AGENTIC_RULES/MAIN_RULES.md` | Contrat de travail, chargement des compléments, autorisation humaine. |
| `AGENTIC_RULES/PROJECT_RULES.md` | Mémoire externe : démarrage, notes, consolidation, panne. |
| `AGENTIC_RULES/WORKFLOW_ENGINEERING.md` | Contrôles techniques, revue indépendante, tests, état persistant. |
| `AGENTIC_RULES/WORKFLOW_GIT.md` | Branches, issues, PR, revue, merge. |
| `AGENTIC_RULES/WORKFLOW_GIT_EPIC.md` | EPIC, Project, train de release RC. |
| `AGENTIC_RULES/REVIEWERS.md` | Un modèle de relecture par fournisseur. |
| `AGENTS.md`, `CLAUDE.md`, `QWEN.md` | Amorçage, quel que soit l'outil agentique. |

`MANIFEST` énumère exactement ce qui est distribué. Un fichier de règles absent
du MANIFEST n'est pas distribué : la CI du dépôt source le refuse.

## Ce qui varie d'un dépôt à l'autre

Un seul fichier, `AGENTIC_RULES/project.config.yml`, créé à l'installation
depuis `project.config.example.yml`. Il porte le nom du projet, sa langue
publique, son connecteur Hivemind, son espace et son fournisseur de relecture. Trois états
par champ, sans ambiguïté possible :

- une valeur, le champ est renseigné et utilisé ;
- `disabled`, le champ est volontairement inutilisé ;
- `TO_FILL`, le champ n'a pas été traité, le contrôle de conformité échoue.

Un champ connu de la génération déclarée mais absent est non traité, comme
`TO_FILL`. Un champ introduit après cette génération vaut `disabled` tant que
la configuration n'est pas migrée. Les champs obligatoires du schéma 4 mémoire
sont contrôlés ; supprimer une clé ne permet pas de passer ce contrôle.

## Installer dans un dépôt

```bash
git clone --depth 1 --branch v1.9.1 https://github.com/Cloud-Temple/agentic-rules.git /tmp/ar
/tmp/ar/AGENTIC_RULES/agentic-rules.sh install /chemin/du/depot --ref v1.9.1 --source /tmp/ar
```

Les exemples utilisent le tag `v1.9.1` une fois publié. Une PR de préparation
ne constitue ni ce tag, ni une release, ni une mise à jour des consommateurs.

L'installation prépare la charge utile complète dans un répertoire d'attente
avant de la basculer : un échec en cours de route ne laisse pas un corpus
hybride. Elle refuse d'écraser un `AGENTS.md` ou des règles déjà présents, sauf
`--force`. Elle écrit ensuite `AGENTIC_RULES/.provenance` avec le tag, le commit
et l'empreinte de chaque fichier, puis crée la configuration à renseigner.

Le vérificateur est vendoré avec le corpus, sous `AGENTIC_RULES/agentic-rules.sh`.
Copier enfin `templates/workflows/agentic-conformity.yml` dans `.github/workflows/`.

## Mettre à jour

```bash
./AGENTIC_RULES/agentic-rules.sh update /chemin/du/depot --ref v1.9.1
```

La mise à jour remplace les fichiers du corpus et préserve
`project.config.yml`. Une modification locale d'un fichier de règles est écrasée :
c'est le comportement voulu, un besoin d'évolution passe par une PR sur ce dépôt.

## Vérifier

```bash
./AGENTIC_RULES/agentic-rules.sh check .
```

Le contrôle hors ligne refuse les dérives suivantes : un fichier du corpus modifié ou
supprimé, un fichier du MANIFEST sans empreinte, une empreinte orpheline
laissée par un MANIFEST amputé, un fichier ajouté dans `AGENTIC_RULES/`, ou une
configuration qui garde des `TO_FILL`. Il valide aussi le format mémoire :
clés requises, espace, connecteur, intervalle et absence de formats mélangés.
Retirer une ligne du MANIFEST ou vider
la provenance de ses empreintes ne fait donc pas passer un dépôt dérivé.

Avec `--remote`, le contrôle compare en plus chaque fichier à la source au tag
vendoré, et échoue si la source est injoignable : une comparaison demandée qui
n'a pas eu lieu n'est pas un succès. Le retard sur le dernier tag publié reste
un simple avertissement, rester en arrière est un retard, pas une dérive.

**Limite assumée du contrôle hors ligne.** Les empreintes vivent dans le dépôt
qu'elles gardent. Qui modifie une règle peut recalculer son empreinte dans le
même commit, et le contrôle local dira conforme. Deux choses le rattrapent, la
revue du diff, où les deux modifications sont visibles côte à côte, et le mode
`--remote`, qui compare à la source et non à la provenance. Un test vérifie
exactement ce scénario, y compris le fait que le contrôle local le laisse
passer : autant que ce soit écrit plutôt que découvert.

## Hivemind et migration depuis Live/Graph

La 1.9.1 adapte le protocole mémoire à Hivemind, qui remplace les anciens
services Live Memory et Graph Memory. Il s'agit d'un changement de protocole,
pas d'une simple retouche de vocabulaire : préparer la migration de l'instance,
des données et des accès avant d'adopter ce profil. La version 1.9.0 et son tag
restent intacts. Ni le script `update` ni ces règles ne déploient Hivemind.

Le [contrat Hivemind](https://github.com/Lesur-ai/hivemind/blob/v1.6.4/docs/AGENT_MEMORY_SETUP.md)
et le [guide de migration](https://github.com/Lesur-ai/hivemind/blob/v1.6.4/docs/MIGRATION_LIVE_GRAPH_TO_HIVEMIND.md)
décrivent le service de référence 1.6.4. Vérifier aussi les capacités réellement
exposées par l'instance cible. Les recommandations de gouvernance de ces guides
ne remplacent pas celles du présent corpus, notamment l'absence de GO
supplémentaire pour une consolidation nécessaire.

Le nouveau modèle, en schéma 4, porte un seul bloc :

```yaml
schema_version: 4
# Autres sections project et review conservées.
memory:
  server: hivemind
  space_id: mon-projet
  consolidation_check_interval_hours: 24
```

Ces identifiants sont illustratifs : reporter le connecteur autorisé et
l'identifiant exact du projet. L'alias `hivemind` ne prouve pas l'identité d'une
instance ; son endpoint est vérifié dans la configuration MCP du client, hors
du dépôt. Un espace homonyme sur une autre instance n'autorise aucune sélection
automatique. Aucun endpoint privé ni secret n'est versionné.

Pour migrer une configuration :

1. Vérifier la migration effective de l'espace et de ses trois horizons, puis
   configurer le connecteur Hivemind autorisé dans le client. Ne pas déduire
   une absence d'un refus d'accès et ne pas créer un espace de remplacement.
2. Reporter les valeurs exactes de `memory.live.server`, `space_id` et de
   l'intervalle dans les clés plates ci-dessus, puis passer au schéma 4. En
   schémas 1 ou 2, un intervalle absent devient explicitement `disabled`, sauf
   choix d'en activer un. Vérifier l'ancien index Graph séparément : aucun
   `memory_id` interne n'est à recopier dans le nouveau profil.
3. Retirer les anciens blocs `memory.live`/`memory.graph` de cette seule
   configuration après cette vérification, sans supprimer leurs données. Les
   deux formats ne doivent pas coexister. Conserver les autres valeurs projet.
4. Contrôler le diff et la conformité, puis établir lecture et écriture utile
   sur l'espace Hivemind selon `PROJECT_RULES.md`. Une correction de routage
   suit sa PR dédiée ; aucune modification d'endpoint ou de droits en effet
   secondaire d'une mise à jour du corpus.

Les configurations imbriquées des schémas 1 à 3 restent lisibles comme alias
pour la migration, si leur connecteur cible déjà Hivemind. Le contrôleur valide
les identifiants et l'intervalle, sans contacter les services. Un intervalle
absent avant le schéma 3 vaut `disabled` ; une clé absente depuis sa génération
est refusée. Les anciennes valeurs `memory.graph.*` ne configurent pas LONG.
La compatibilité de format n'autorise aucun repli vers les services Live/Graph.
`update` préserve chaque octet de la configuration : la migration reste une
modification explicite et vérifiable.

## Reprise, consolidation et LONG

Le démarrage charge les règles et MID par `space_summary`, ou les lectures
`space_rules`/`mid_*` appropriées, puis les notes `short_read`. La complétude
est vérifiée avec les totaux et tailles du service. Une note durable s'écrit
par `short_note` ; l'identité provient du jeton, pas d'un paramètre d'auteur.
Les relecteurs indépendants établissent personnellement la lecture et restent
en lecture seule, sans création d'espace ni note mémoire.

Le coordinateur contrôle la banque à la reprise et aux jalons. Pendant les
longues sessions, l'intervalle est un entier positif en heures ; `24` est le
réglage initial, `disabled` désactive cette seule échéance. Il ne crée aucun
minuteur. Le contrôle porte sur les nouveautés, la fraîcheur et les budgets,
pas sur une consolidation aveugle à chaque réveil.

`mid_consolidate` soumet un travail asynchrone. L'accusé n'est pas une réussite ;
le périmètre par défaut est celui de l'appelant. Respecter le retour sans
polling ; le statut détaillé exige une demande explicite de l'utilisateur dans
le contrat actuel. Ne pas déclencher une opération LONG comme effet secondaire.
`long_query` retrouve des sources ; `long_push` est une mutation pouvant créer
une liaison. `long_ingest` en 1.6.4 prépare un plan et ne prend pas en charge
`apply` : ne pas le présenter comme une ingestion effectuée.

## Tests

```bash
./scripts/test/run.sh
```

Des assertions de distribution sur une source git isolée à deux versions taggées et des
dépôts consommateurs jetables, sans accès réseau, avec des chemins contenant une
espace. Elles couvrent l'installation, le refus d'écraser un fichier existant,
la détection d'un fichier modifié puis supprimé, les trois contournements du
contrôle, la montée de version avec retrait d'un fichier sorti de la charge
utile, la préservation de la configuration, le fait qu'un refus laisse la cible
strictement inchangée, et le nettoyage des temporaires. Elles couvrent aussi
le schéma mémoire 4, les anciens formats, les champs manquants, les formats
mélangés, les valeurs invalides et la configuration préservée lors de la mise
à jour. Les contrôles source et consommateur utilisent le même validateur
versionné `AGENTIC_RULES/config.sh`. Ces tests ne prouvent pas le comportement
des agents ni une migration d'instance réelle.

Trois scénarios viennent de constats de revue : une mise à jour dont la bascule
échoue à mi-chemin doit rendre la cible intacte, un MANIFEST portant un chemin
remontant ne doit rien supprimer hors de la cible, et un répertoire occupant le
chemin d'un fichier du corpus doit faire échouer l'installation au lieu d'y
imbriquer le fichier.

Deux assertions gardent des défauts déjà rencontrés : la configuration doit
rester hors empreinte, sans quoi tout dépôt renseigné serait vu comme dérivé, et
un `TO_FILL` cité dans un commentaire ne doit pas faire échouer le contrôle,
sans quoi un dépôt correctement configuré resterait non conforme à vie.

## Versionnement

Ce dépôt suit le versionnement sémantique à partir de `v1.0.0`.

- Une version majeure introduit une incompatibilité réelle avec un contrat
  existant : outil ou configuration devenus incompatibles, chemin distribué
  supprimé ou déplacé sans maintien de compatibilité.
- Une version mineure ajoute une évolution compatible, y compris une obligation
  de pilotage qui conserve les contrats d'outils, les configurations et les
  chemins distribués existants.
- Une version corrective corrige un défaut sans introduire de nouveau contrat.

Toute évolution de comportement est décrite dans le changelog. Les dépôts
consommateurs doivent relire les règles modifiées avant une mise à jour, même
mineure ; compatible ne signifie pas sans effet sur le travail de l'agent.
