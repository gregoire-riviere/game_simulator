* Reste simple, minimaliste dans tes modifications. Tu dois écrire le moins de code possible.
* Garde de la lisibilité et de la capacité à mainteir
* Minimise les dépendances externe, tu peux me demander avant d'ajouter une dependance
* Ne cherche pas à surfactoriser le code. l'objectif est que ce soit lisible
* Pas de `defp` en elixir
* Pense bien aux aspect secu
* Lorsque tu introduits des nouvelles fonctionnalités importantes, tâche de découpler
* Quand tu introduits des calcul/lignes compliquées, ajoute un petit commentaire avant
* Pas de mix format sur fichier deja existant, sauf demande explicite!

## Architecture à respecter
* Les mécaniques de jeu ne sont jamais confiés aux llm. Elles sont toujours implémenter de façon deterministe dans l'outil, les llm, quand ils sont là, ne sont utilisés que pour la décision

## Base de donnée
* Tu vises la simplicité des modèles de donnée, des choses maintenanbles, claires et simples
* Le moins de choses possible en bdd, juste le nécessaire
* Pas de requêtes ultra complexes, ou alors demande moi
* On introduit jamais une nouvelle deps sans me consulter