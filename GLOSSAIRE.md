# Glossaire poker

Ce glossaire regroupe les principaux termes de poker utilisés par le simulateur, en particulier pour une table de Texas Hold'em No Limit micro-limites.

## Déroulement d'une main

| Terme | Définition |
| --- | --- |
| Main | Coup complet joué entre la distribution des cartes privées et le règlement du pot. |
| Préflop | Premier tour d'enchères, avant toute carte commune. |
| Flop | Trois premières cartes communes révélées au centre de la table. |
| Turn | Quatrième carte commune révélée après le flop. |
| River | Cinquième et dernière carte commune révélée. |
| Showdown | Abattage des cartes quand plusieurs joueurs restent après la river. La meilleure main de cinq cartes gagne le pot concerné. |
| Board | Ensemble des cartes communes visibles par tous les joueurs. |
| Cartes privées | Deux cartes distribuées à chaque joueur, visibles seulement par lui. |
| Rue | Tour de jeu courant : préflop, flop, turn ou river. |
| Dealer / Bouton | Position de référence qui tourne à chaque main et sert à déterminer l'ordre de parole. |

## Jetons, mises et pots

| Terme | Définition |
| --- | --- |
| Cave | Montant de jetons avec lequel un joueur entre à table. Dans le simulateur, une cave vide empêche de démarrer une nouvelle main. |
| Stack | Jetons restants devant un joueur à un instant donné. |
| Pot | Total des jetons engagés dans la main et à gagner. |
| Pot principal | Pot accessible à tous les joueurs encore éligibles, notamment quand un joueur est à tapis avec moins de jetons. |
| Side pot | Pot secondaire créé quand des joueurs continuent à miser au-delà du tapis d'un autre joueur. |
| Small blind | Mise obligatoire postée par le joueur à gauche du bouton, sauf cas particuliers en heads-up. |
| Big blind | Mise obligatoire postée après la small blind ; elle sert aussi de référence aux montants minimaux de mise. |
| Contribution | Jetons déjà engagés par un joueur dans la main ou dans la rue courante. |
| Current bet | Plus grande contribution à égaler pendant la rue courante. |
| To call | Montant restant à payer pour suivre la mise courante. |
| Min raise | Écart minimal requis pour qu'une relance soit légale. |
| Tapis / All-in | Action d'engager tout son stack restant. |
| Recave | Recharger une nouvelle cave après avoir perdu ses jetons. |

## Actions

| Terme | Définition |
| --- | --- |
| Fold / Se coucher | Abandonner la main et renoncer au pot. |
| Check / Parole | Ne rien miser quand aucune mise n'est à payer. |
| Call / Suivre | Payer le montant nécessaire pour égaler la mise courante. |
| Bet / Miser | Ouvrir les enchères sur une rue où personne n'a encore misé. |
| Raise / Relancer | Augmenter une mise déjà ouverte. |
| Raise to | Montant total visé par la relance, pas seulement le supplément ajouté. |
| C-bet / Continuation bet | Mise postflop faite par l'agresseur préflop. |
| Limp | Se contenter de suivre la big blind préflop sans relancer. |
| Overplay | Jouer une main correcte comme si elle était beaucoup plus forte. |
| Bluff | Miser ou relancer avec une main faible pour faire coucher l'adversaire. |

## Positions

| Terme | Définition |
| --- | --- |
| Early position | Position qui parle tôt après les blinds ; elle exige généralement des mains plus fortes. |
| Hijack | Position située deux sièges avant le bouton sur une table complète. |
| Cutoff | Position juste avant le bouton. |
| Button | Joueur au bouton ; position très avantageuse postflop car elle parle souvent en dernier. |
| Small blind | Position de la petite blind, hors position après le flop. |
| Big blind | Position de la grosse blind, qui a déjà engagé une mise obligatoire. |
| Heads-up | Main jouée à deux joueurs. |

## Profils et statistiques des joueurs

| Terme | Définition |
| --- | --- |
| VPIP | Voluntarily Put Money In Pot : pourcentage de mains où un joueur engage volontairement des jetons préflop. Un VPIP élevé indique un joueur large. |
| PFR | Preflop Raise : pourcentage de mains où un joueur relance préflop. |
| 3-bet | Surrelance préflop après une première relance. |
| Fold to c-bet | Fréquence à laquelle un joueur se couche face à un continuation bet. |
| Aggression | Tendance à miser ou relancer plutôt qu'à checker ou payer. |
| Showdown curiosity | Tendance à payer, surtout river, pour voir la main adverse. |
| Tilt | État émotionnel négatif qui pousse à jouer moins rationnellement. |
| Tilt resistance | Capacité d'un profil à limiter l'effet du tilt sur ses décisions. |
| Bluff frequency | Propension d'un joueur à transformer des mains faibles en mises ou relances. |
| Weird sizing frequency | Fréquence de sizings inhabituels ou peu standards. |
| Stupid mistake frequency | Probabilité de faire une erreur simple ou incohérente. |
| Call too wide | Tendance à payer avec une range trop large. |
| Chases draws | Tendance à payer trop souvent avec des tirages. |
| Fish passif | Joueur faible qui joue trop de mains et paie trop souvent. |
| TAG | Tight Aggressive : joueur sélectif préflop et agressif quand il entre dans un coup. |
| Nit | Joueur très serré qui attend surtout de très bonnes mains. |
| LAG | Loose Aggressive : joueur large et agressif qui met souvent la pression. |
| Maniaque | Joueur très agressif, avec beaucoup de relances et de sizings variables. |
| Récréatif | Joueur non professionnel, souvent imparfait et imprévisible. |

## Mains, ranges et tirages

| Terme | Définition |
| --- | --- |
| Range | Ensemble des mains possibles qu'un joueur peut avoir selon son action et sa position. |
| Combo | Combinaison précise de deux cartes privées. Par exemple, une paire servie possède 6 combos possibles. |
| Suited | Deux cartes privées de la même couleur, notées avec `s` comme `AKs`. |
| Offsuit | Deux cartes privées de couleurs différentes, notées avec `o` comme `AKo`. |
| Paire | Deux cartes de même rang. |
| Double paire | Deux paires distinctes. |
| Brelan | Trois cartes de même rang. |
| Quinte | Cinq cartes qui se suivent. |
| Couleur / Flush | Cinq cartes de la même couleur. |
| Full | Un brelan plus une paire. |
| Carré | Quatre cartes de même rang. |
| Quinte flush | Cinq cartes consécutives de la même couleur. |
| Carte haute | Main sans combinaison, départagée par la carte la plus forte. |
| Nuts | Meilleure main possible dans une situation donnée. |
| Air | Main très faible, généralement sans paire ni tirage important. |
| Top pair | Paire faite avec la plus haute carte du board. |
| Tirage couleur | Situation avec quatre cartes de la même couleur et une carte manquante pour faire couleur. |
| Tirage quinte | Situation où une carte manquante permet de faire quinte. |
| Open-ended | Tirage quinte par les deux bouts : deux rangs différents peuvent compléter la quinte. |
| Gutshot | Tirage quinte ventral : une seule valeur au milieu complète la quinte. |
| Combo draw | Tirage combiné, par exemple tirage couleur plus tirage quinte. |
| Outs | Cartes restantes dans le paquet qui peuvent améliorer une main. |
| Equity | Part estimée du pot qu'une main peut gagner à long terme contre une range adverse. |

## Paramètres du simulateur

| Terme | Définition |
| --- | --- |
| Phase | État courant de la main : attente, préflop, flop, turn ou river. |
| Active player | Joueur dont l'action est attendue. |
| Players in hand | Nombre de joueurs encore actifs dans la main. |
| Pending | Joueurs qui doivent encore parler dans la rue courante. |
| Folded | Joueurs couchés pendant la main. |
| All-in | Joueurs encore dans le coup mais sans jeton restant. |
| Street aggressor | Dernier joueur ayant misé ou relancé pendant la rue courante. |
| Preflop aggressor | Dernier relanceur préflop, utilisé pour détecter un c-bet. |
| Hand history | Historique récent des mains terminées, incluant résultats, board et gagnants. |
| Profit / loss | Gain ou perte nette d'un joueur sur une main. |
| Bad beat | Coup perdu malgré une main très favorite au moment où les jetons partent au milieu. |
