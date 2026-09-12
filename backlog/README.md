# Backlog Markdown

Ce dossier remplace Trello. Il est volontairement compact : lire d'abord `board.md`, puis uniquement la fiche liée si nécessaire.

- `board.md` : source de vérité des états et des actions en cours.
- `items/<ID>.md` : détail d'une fiche seulement quand un brief, des critères ou des notes de review ne tiennent pas sur une ligne.
- Ne pas créer de sous-dossiers par statut : déplacer une ligne dans `board.md`.
- Archiver les fiches terminées dans `Done` ; ne conserver que les 20 dernières, puis les supprimer du board (l'historique Git reste disponible).

## Format d'une ligne

`ID | titre | type | priorité | lien | prochaine action`

Types : `feature`, `bug`, `chore`, `tech`. Priorités : `P0` à `P3`.
Le lien est une fiche `items/ID.md` ou une PR GitHub. Laisser `-` si absent.

## Flux

`Ideas → Backlog PO → Ready for dev → Dev → Review → Done`

- PO : ajoute ou précise une ligne.
- QA : ajoute les critères et les tests attendus dans la fiche, puis passe en **Ready for dev**.
- Dev : renseigne la PR et passe en **Review** après les tests.
- Review : passe en **Done** ou écrit les changements demandés dans la fiche.

Les agents ne doivent modifier que la ligne ou la fiche concernée.
