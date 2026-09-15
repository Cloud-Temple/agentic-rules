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
curl -fsSL -o /tmp/agentic-rules.sh \
  https://raw.githubusercontent.com/Cloud-Temple/agentic-rules/main/scripts/agentic-rules.sh
chmod +x /tmp/agentic-rules.sh
/tmp/agentic-rules.sh install /chemin/du/depot --ref v1.0.0
```

L'installation copie la charge utile, écrit `AGENTIC_RULES/.provenance` avec le
tag, le commit et l'empreinte de chaque fichier, puis crée la configuration à
renseigner. Copier ensuite `templates/workflows/agentic-conformity.yml` dans
`.github/workflows/` du dépôt.

## Mettre à jour

```bash
/tmp/agentic-rules.sh update /chemin/du/depot --ref v1.1.0
```

La mise à jour remplace les fichiers du corpus et préserve
`project.config.yml`. Une modification locale d'un fichier de règles est écrasée :
c'est le comportement voulu, un besoin d'évolution passe par une PR sur ce dépôt.

## Vérifier

```bash
/tmp/agentic-rules.sh check /chemin/du/depot --remote
```

Le contrôle échoue si un fichier du corpus a été modifié ou supprimé, ou si la
configuration garde des `TO_FILL`. Avec `--remote`, il avertit en plus lorsque
le dépôt est resté sur un tag antérieur au dernier publié. Cet avertissement ne
fait pas échouer le job : rester en arrière est un retard, pas une dérive.

## Tests

```bash
./scripts/test/run.sh
```

Vingt-deux assertions sur une source git isolée et un dépôt consommateur
jetable, sans accès réseau : installation, refus de double installation,
détection d'un fichier modifié puis supprimé, réparation par mise à jour,
préservation de la configuration, et vérification que la configuration reste
hors empreinte pour qu'un dépôt renseigné ne soit jamais vu comme dérivé.

## Versionnement

Ce dépôt suit le versionnement sémantique à partir de `v1.0.0`. Un changement
qui rend une règle plus contraignante ou déplace un fichier est une version
majeure : les dépôts consommateurs doivent alors relire avant de mettre à jour.
