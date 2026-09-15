# Corpus de règles agentiques Cloud Temple

Les règles de travail que suivent les agents sur les dépôts Cloud Temple :
contrat de travail, mémoire externe obligatoire, discipline d'ingénierie,
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
publique, ses identifiants mémoire et son fournisseur de relecture. Trois états
par champ, sans ambiguïté possible :

- une valeur, le champ est renseigné et utilisé ;
- `disabled`, le champ est volontairement inutilisé ;
- `TO_FILL`, le champ n'a pas été traité, le contrôle de conformité échoue.

Un champ absent est traité comme `TO_FILL`. Supprimer une clé ne fait pas
passer le contrôle, cela le fait échouer autrement.

## Installer dans un dépôt

```bash
git clone --depth 1 --branch v1.0.0 https://github.com/Cloud-Temple/agentic-rules.git /tmp/ar
/tmp/ar/AGENTIC_RULES/agentic-rules.sh install /chemin/du/depot --ref v1.0.0 --source /tmp/ar
```

L'installation prépare la charge utile complète dans un répertoire d'attente
avant de la basculer : un échec en cours de route ne laisse pas un corpus
hybride. Elle refuse d'écraser un `AGENTS.md` ou des règles déjà présents, sauf
`--force`. Elle écrit ensuite `AGENTIC_RULES/.provenance` avec le tag, le commit
et l'empreinte de chaque fichier, puis crée la configuration à renseigner.

Le vérificateur est vendoré avec le corpus, sous `AGENTIC_RULES/agentic-rules.sh`.
Copier enfin `templates/workflows/agentic-conformity.yml` dans `.github/workflows/`.

## Mettre à jour

```bash
./AGENTIC_RULES/agentic-rules.sh update /chemin/du/depot --ref v1.1.0
```

La mise à jour remplace les fichiers du corpus et préserve
`project.config.yml`. Une modification locale d'un fichier de règles est écrasée :
c'est le comportement voulu, un besoin d'évolution passe par une PR sur ce dépôt.

## Vérifier

```bash
./AGENTIC_RULES/agentic-rules.sh check .
```

Le contrôle hors ligne échoue dans cinq cas : un fichier du corpus modifié ou
supprimé, un fichier du MANIFEST sans empreinte, une empreinte orpheline
laissée par un MANIFEST amputé, un fichier ajouté dans `AGENTIC_RULES/`, ou une
configuration qui garde des `TO_FILL`. Retirer une ligne du MANIFEST ou vider
la provenance de ses empreintes ne fait donc pas passer un dépôt dérivé.

Avec `--remote`, le contrôle compare en plus chaque fichier à la source au tag
vendoré. C'est la seule vérification qui ne repose pas sur un fichier que le
dépôt contrôle lui-même, et elle demande un accès sortant. Le retard sur le
dernier tag publié n'est qu'un avertissement : rester en arrière est un retard,
pas une dérive.

## Tests

```bash
./scripts/test/run.sh
```

Trente-neuf assertions sur une source git isolée à deux versions taggées et des
dépôts consommateurs jetables, sans accès réseau, avec des chemins contenant une
espace. Elles couvrent l'installation, le refus d'écraser un fichier existant,
la détection d'un fichier modifié puis supprimé, les trois contournements du
contrôle, la montée de version avec retrait d'un fichier sorti de la charge
utile, la préservation de la configuration, le fait qu'un refus laisse la cible
strictement inchangée, et le nettoyage des temporaires.

Deux assertions gardent des défauts déjà rencontrés : la configuration doit
rester hors empreinte, sans quoi tout dépôt renseigné serait vu comme dérivé, et
un `TO_FILL` cité dans un commentaire ne doit pas faire échouer le contrôle,
sans quoi un dépôt correctement configuré resterait non conforme à vie.

## Versionnement

Ce dépôt suit le versionnement sémantique à partir de `v1.0.0`. Un changement
qui rend une règle plus contraignante ou déplace un fichier est une version
majeure : les dépôts consommateurs doivent alors relire avant de mettre à jour.
