# Traversal: rules and implementation

Rules checked on 25 October 2026 against https://www.traversalgame.com/rules,
the official RulesPage English text/tutorial and the public game runtime
served by that site (entry `index-CP7eMlg-.js`). The site links its public project
from About: https://github.com/darkfireXXI/board_game. The rules engine here is an
independent Elixir implementation. No official source code or visual asset is
copied. The fixture contains observable positions/actions only, obtained by
running the public runtime: 16 situations, 1,440 legal actions, flat terrain and
three varied generated terrains, followed by one move per situation.

## Rules resolved against the running game

- 10×10, integer elevations 0–5, neighbouring elevation differences ≤2.
  Each side begins with Sentinel, Vanguard, Explorer, Explorer, Vanguard, Sentinel
  in columns C–H; the human starts on row 10 and moves toward row 1.
- Explorer: movement 5, strength 1; Vanguard: 4/2; Sentinel: 3/3.
  Normal movement is orthogonal, may turn, and each step costs
  `1 + abs(destination height - previous height)`. Occupied cells cannot be
  crossed. A legal capture may follow normal movement and ends the turn.
- Combat requires attack ≥ defence. Compare the attacker's **turn origin**
  elevation with the target: +1 higher, −1 lower. Add the base strengths of
  friendly pieces orthogonally adjacent to the target, excluding the attacker.
  Defence adds 1 for each friendly piece orthogonally adjacent to the defender.
  Vanguard adds 1 only when the **minimum** normal path cost to that target is
  exactly 4: an artificial detour never grants charge.
- Explorer may instead move one diagonal or jump two cardinal cells, ignoring
  elevation. A jump's intermediate cell must be empty (either colour blocks it).
  This is the whole turn, cannot combine with normal travel, and may capture
  if combat succeeds. Diagonal movement from the last row, or a forward jump
  from the penultimate row, may exit. Normal destinations take precedence over
  a special destination, including an attack denied by normal combat checks,
  matching the public runtime. The UI marks special actions as powers.
- Normal exit costs 1 movement point from the opposite last row; it can follow
  normal travel if enough points remain. An exited piece earns its strength.
  If the very first exit by either side is a Sentinel, that side wins immediately.
  Otherwise, **two exits total**, even by different sides, end play on scores;
  equal scores draw. Sentinel exiting second does not grant instant victory.
- If either side has no active pieces (captured or exited), add each side's
  strongest remaining active piece to its exit score, then compare scores.
- After **200 individual moves**, compare exit scores. On equality, compare
  the closest active piece's remaining row distance, then its base strength.
  If these also tie, draw. This follows the public runtime even when equal
  scores are nonzero; the prose rules only describe the no-score example.
- Three consecutive repetitions of an entire even-length position sequence
  draw. This is not simply three scattered occurrences of one position.
  Active piece type/player/coordinates, turn and exited pieces identify positions.
- The official text/runtime provides no outcome or passing rule for a player
  with no legal action. This application displays **no legal move / blocked**,
  offers a new game, and does not invent a winner, pass, or bot polling loop.

## Authoritative sessions and bots

One temporary GenServer per authenticated account uses the existing registry
and dynamic supervisor, with 30-minute idle expiry. Every API call checks the
account's current `traversal` permission. The client sends a generated terrain
only when starting a game; the server validates shape, heights, all eight slopes
and central symmetry. The server creates every piece, legal action and result.
Seed metadata (at most 80 characters) is retained for reopening the view.
Moves include an unpredictable game ID and revision. Other accounts never select
that session; stale, wrong-turn and illegal requests are rejected. Bot messages
carry the same version and cannot act after replacement or game over. No persistence,
multiplayer, LLM or new dependency is introduced.

Easy chooses the highest immediate heuristic value. Medium anticipates one
opponent reply (depth 2, beam 12, at most 500 searched nodes, 800 ms deadline).
Hard adds its own next move (maximum depth 3, beam 18, at most 2,500 searched nodes, 1,600 ms).
Medium and hard complete depth 2 before trying a deeper root iteration; an
interrupted iteration keeps the last complete choice, or the ranked fallback
if no iteration completed. The node budget is shared across iterations.
Equivalent exit columns for a given piece are collapsed in search only; all
legal exit choices remain available to the human. When facing an immediate
winning threat, medium and hard retain verified defensive moves whenever found.
All levels rank terminal wins/losses before positional values. The shared
heuristic weights exit scores, strength/captures, progression, early Sentinel
progression, terrain costs, adjacent support and immediate threats. Weighted
distance fields to the exit are computed once per side for each decision and
reused during search; they include elevation costs and ignore occupants.
Medium and hard also plan interception of opposing Sentinels advanced at least
three rows. For each, up to four legal fastest-advance positions are projected.
The two strongest defenders (distance breaks ties) get reverse capture fields:
whole turns of legal movement ending in a legal capture, with actual terrain,
occupants, strength, support and forest stopping rules. At most 1,600 bounded
100-cell-origin legal queries build these fields once per decision. Search then
reuses their interception margin instead of waiting for adjacent danger. A prior
Explorer/Vanguard exit does not erase a Sentinel's potential winning second exit.
These are positional estimates: the projected route, blockers and supports stay
fixed during search, and a rival can change its route. They do not prove a forced
capture. Easy keeps its immediate scoring behavior.

Search uses
alpha-beta pruning; legal generation itself is bounded to 6 pieces and 100 cells.
The monotonic search deadline begins after the fixed terrain/interception
precomputation and before root ranking; a currently running bounded
legal-generation/ranking operation may finish after the deadline. This is a
bounded algorithm, not a hard real-time guarantee. Node limits count searched
descendants, not every heuristic evaluation used to rank legal moves or check
immediate threats. No external calls are used. Tactical regressions distinguish
greedy scoring from necessary defence and verify a forced Sentinel finish
beyond the medium horizon; these examples do not imply a stronger level wins
every match.

## Client and validation

Click a blue piece for blue movement rings, red capture diamonds and green exit
rings outside the board. The destination buttons provide the same actions and
combat values for keyboard use. Drag/zoom does not trigger moves. Request
cancellation, generation checks, disposed checks and timer cleanup prevent stale
view callbacks; server revisions guard the game independently.

Shapes are original Three.js solids following the official silhouettes:
Explorer pentagonal pyramid (one apex), Vanguard quadrilateral wedge (two upper
vertices), Sentinel triangular prism (three upper vertices). Colours identify
sides; yellow marks selection. The approved seeded terrain generator is unchanged.

Run `npm ci && npm run prepare:vendor && npm test`, `mix test`, then
`mix install_minifiers && mix compile_front`. Elixir tests cover rules, the
independent official corpus, tactical bots, budgets, session/version isolation
and permission-protected API requests. Node tests cover terrain and closed
piece geometry. Manually verify WebGL desktop/mobile: select/deselect, legal
attack vs movement/exit, orbit vs click, keyboard actions, all difficulties,
loading, terminal state and leaving/reopening the view. Browser validation must
be reported separately from compilation and algorithmic tests.

## Variante Forêts

Le sélecteur Classique / Forêts s’applique à la nouvelle partie. Le serveur conserve
la variante et génère depuis la graine (80 caractères maximum) exactement deux
forêts carrées 2 × 2, distinctes et symétriques par rotation de 180°. Les cases
restent intérieures, hors départs et bords de sortie. Le relief approuvé est inchangé.
La variante classique et les anciennes requêtes sans variante restent compatibles.

Entrer dans une forêt termine immédiatement le tour : elle peut être une destination,
jamais une étape intermédiaire de marche. Depuis une forêt, la marche normale est
limitée à un seul pas orthogonal, pour déplacement ou capture ; une sortie directe
est possible si la pièce commence sur le dernier rang. Le relief, le combat et les
soutiens ne changent pas. La charge Vanguard utilise toujours le vrai coût minimal.
Explorer conserve sa diagonale et son saut cardinal de deux cases comme action unique,
pour déplacement, capture ou sortie ; une forêt vide ne bloque pas la case sautée,
une pièce la bloque. Ces pouvoirs ne se combinent pas avec la marche.

Les trois bots choisissent exclusivement parmi les actions légales du moteur ; leur
estimation de distance ajoute un coût de 2 PM par entrée en forêt, approximation du
ralentissement sans modifier les coûts réels ni la recherche bornée. Les arbres
sont décoratifs, hors raycast, et les cases « F » sont aussi lisibles dans la table.


## Lateral Sentinel rush regressions

A legal scripted human commits its initial left/right Sentinel to the flank,
then advances on that flank. Regression tests cover both sides and medium/hard
on flat terrain, a symmetric ridge, and exact generated `rush-0` / `rush-1`
boards; flat/ridge cases also run in Forêts. The previous medium bot lost the
right flank on `rush-0` and both flanks on `rush-1`; the interception heuristic
captures these runners. Additional tests cover a full developed formation's
response time, weak defenders, an occupied wall, forest slowdown and a winning
Sentinel second exit. Existing immediate-win, forced-finish and three-level tests
remain in place.

This is stronger play, not a guarantee against every rush. Exploratory generated
positions still reveal weaknesses, including a winning offensive race abandoned
on `rush-11` right flank, and hard Forêts on `rush-1` left flank. Those positions
are not represented as solved. Search results can vary with machine load when
the deadline interrupts an iteration. Browser validation remains separate.

## Variantes combinables : étendue et forêts

Les options sont indépendantes : étendue (12 × 12 et un canon supplémentaire par
camp) et forêts 2 × 2 symétriques peuvent être combinées. Les requêtes existantes
`classic` et `forests` restent valides ; les autres combinaisons utilisent les noms
séparés par `+`. Les plateaux sont validés pour la taille associée à la variante.
Toutes les rangées sont traversables selon les règles normales de déplacement.

Le canon (force 2, déplacement 2) se déplace ou tire. Son tir orthogonal de 2 à
3 cases capture sans déplacer le canon ; les pièces intermédiaires bloquent le
tir, ainsi qu'une cible plus haute. Les règles de combat et de soutien habituelles
s'appliquent. Il ne peut pas tirer depuis une forêt ni attaquer à une case.
Sa sortie vaut 2 points.

Les bots utilisent les coups légaux du moteur pour leurs recherches. Leurs champs
de distance tiennent compte du relief et des forêts, sans obstacle périodique.
Les budgets
temporels restent bornés, sans garantie de niveau équivalent sur le plateau étendu.
