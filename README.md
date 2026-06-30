# Game Simulator

[English version](README.en.md)

Game Simulator est une application Elixir qui expose une interface web locale et
une API JSON pour jouer des mains de poker contre des PNJ. Elle peut tourner en
developpement avec `mix` ou en production via une release Mix.

Le projet contient aujourd'hui :

- un serveur HTTP Plug/Cowboy ;
- une interface statique compilee depuis `web/` vers `priv/static/` ;
- une authentification locale SQLite avec permissions et tokens signes ;
- une table temporaire par utilisateur authentifie ;
- un moteur de poker NL2 6-max avec PNJ heuristiques ;
- un shadow mode LLM optionnel pour auditer des decisions sans modifier le jeu.

## Table des matieres

- [Documentation utilisateur](#documentation-utilisateur)
  - [Prerequis](#prerequis)
  - [Installation et demarrage](#installation-et-demarrage)
  - [Creer un utilisateur](#creer-un-utilisateur)
  - [Jouer](#jouer)
  - [Configurer l'application](#configurer-lapplication)
  - [Shadow mode LLM](#shadow-mode-llm)
  - [Release](#release)
  - [Exposer avec HAProxy](#exposer-avec-haproxy)
- [Documentation developpeur](#documentation-developpeur)
  - [Organisation du projet](#organisation-du-projet)
  - [Commandes de developpement](#commandes-de-developpement)
  - [API HTTP](#api-http)
  - [Poker et PNJ](#poker-et-pnj)
  - [Client web](#client-web)
  - [Securite](#securite)

## Documentation utilisateur

### Prerequis

- Elixir `~> 1.19` avec une version Erlang/OTP compatible.
- `mix` et Hex (`mix local.hex` si necessaire).
- Les outils de minification installes par `mix install_minifiers` pour compiler
  le client web.

### Installation et demarrage

```sh
git clone <repository-url> game_simulator
cd game_simulator
mix deps.get
cp .env.example .env
mix install_minifiers
mix compile_front
mix run --no-halt
```

Par defaut, le serveur ecoute sur `http://127.0.0.1:4000`.

`.env` est optionnel en developpement : des valeurs par defaut existent deja. Le
fichier est ignore par Git ; ne committez que `.env.example`.

### Creer un utilisateur

La creation d'utilisateur se fait actuellement depuis le serveur. Les mots de
passe doivent contenir au moins 12 caracteres.

```sh
mix run -e 'IO.inspect(GameSimulatorWeb.Users.add("admin", "a-long-unique-password", ["admin"]))'
```

Les utilisateurs sont stockes dans la table SQLite `users`. Les permissions
valides sont `admin`, `poker` et `llm`; `admin` donne acces a tout. Si un ancien
fichier `GAME_SIMULATOR_USERS_FILE` existe au premier demarrage, ses comptes sont
importes une fois comme admins.

Apres 5 tentatives de connexion echouees d'affilee, le compte est bloque pendant
12 heures, y compris pour les admins. Un admin peut le debloquer depuis
l'interface d'administration, ou en console :

```sh
mix run -e 'IO.inspect(GameSimulatorWeb.Users.unlock("admin"))'
```

### Jouer

Une fois le serveur lance, ouvrez `http://127.0.0.1:4000`, connectez-vous, puis
demarrez une table depuis l'interface.

Le mode actuel cible une table cash-game NL2 6-max simplifiee :

- blindes `1/2`, representees en centimes entiers ;
- stack initial de `200` par joueur ;
- hero au siege 6, cinq PNJ aux sieges 1 a 5 ;
- recave automatique a `200` quand un stack passe sous `80` ;
- pas de rake dans cette V1.

Les PNJ utilisent des heuristiques locales, pas des appels LLM.

### Configurer l'application

La configuration est resolue au demarrage, avec le meme comportement en `mix` et
en release. L'ordre de priorite est :

1. Variables d'environnement systeme.
2. Fichier indique par `GAME_SIMULATOR_ENV_FILE`.
3. Fichier par defaut : `.env` en developpement/release, `.env.test` en test.
4. Valeurs par defaut integrees.

En release, le `.env` par defaut est cherche a la racine de la release. Si la
configuration est geree ailleurs, renseignez `GAME_SIMULATOR_ENV_FILE` avec un
chemin absolu. Les variables systeme restent prioritaires.

| Variable | Dev/test | Production | Description |
| --- | --- | --- | --- |
| `GAME_SIMULATOR_HOST` | `127.0.0.1` | `0.0.0.0` | Interface d'ecoute HTTP. Doit etre une adresse IP. |
| `GAME_SIMULATOR_PORT` | `4000` | `4000` | Port HTTP, entre 1 et 65535. |
| `GAME_SIMULATOR_LOG_DIR` | `<project>/log` / dossier temporaire en test | `<release>/log` | Dossier contenant `info.log` et `debug.log`. |
| `GAME_SIMULATOR_LOG_LEVEL` | `debug` | `debug` | Seuil console : `debug`, `info`, `warning` ou `error`. |
| `GAME_SIMULATOR_DATA_DIR` | `<project>/data` / dossier temporaire en test | `<release>/data` | Donnees locales, dont SQLite et le secret de signature des tokens. |
| `GAME_SIMULATOR_USERS_FILE` | `<data-dir>/users` | `<data-dir>/users` | Chemin d'import legacy optionnel pour l'ancien fichier utilisateurs. |
| `GAME_SIMULATOR_TOKEN_TTL_SECONDS` | `86400` | `86400` | Duree de vie des tokens signes, en secondes. |
| `GAME_SIMULATOR_LLM_ENABLED` | `false` | `false` | Active les appels LLM de shadow decision. |
| `GAME_SIMULATOR_LLM_SHADOW_MODE` | `true` | `true` | Garde les decisions LLM en observation uniquement. |
| `GAME_SIMULATOR_LLM_PROVIDER` | `openrouter` | `openrouter` | Provider LLM supporte. |
| `GAME_SIMULATOR_LLM_API_KEY` | non defini | non defini | Cle OpenRouter, requise si les appels LLM sont actives. |
| `GAME_SIMULATOR_LLM_BASE_URL` | `https://openrouter.ai/api/v1` | idem | URL OpenRouter-compatible. Doit etre en HTTPS. |
| `GAME_SIMULATOR_LLM_DECISION_MODEL` | `google/gemini-2.5-flash` | idem | Modele utilise pour les shadow decisions. |
| `GAME_SIMULATOR_LLM_TIMEOUT_MS` | `1500` | `1500` | Timeout maximum d'un appel LLM. |
| `GAME_SIMULATOR_LLM_INTEREST_THRESHOLD` | `4` | `4` | Score minimum avant d'appeler le LLM. |
| `GAME_SIMULATOR_LLM_AUDIT_FILE` | `data/llm_shadow_audit.ndjson` | idem | Journal NDJSON des shadow decisions. |
| `GAME_SIMULATOR_LLM_HTTP_REFERER` | non defini | non defini | Header OpenRouter optionnel. |
| `GAME_SIMULATOR_LLM_X_TITLE` | `game_simulator` | idem | Header OpenRouter optionnel. |
| `GAME_SIMULATOR_ENV_FILE` | selon l'environnement | `<release>/.env` | Fichier dotenv optionnel. |

Les chemins relatifs sont resolus depuis la racine du projet ou de la release.
`debug.log` conserve tous les evenements applicatifs. `info.log` conserve les
evenements `:info`, `:warning` et `:error`. Le niveau configure ne concerne que
la sortie console.

Exemple minimal :

```dotenv
GAME_SIMULATOR_HOST=127.0.0.1
GAME_SIMULATOR_PORT=4000
GAME_SIMULATOR_LOG_DIR=log
GAME_SIMULATOR_LOG_LEVEL=debug
GAME_SIMULATOR_DATA_DIR=data
GAME_SIMULATOR_TOKEN_TTL_SECONDS=86400
GAME_SIMULATOR_LLM_ENABLED=false
```

### Shadow mode LLM

Le shadow mode LLM est optionnel. Quand il est active, il audite certains spots
interessants sans piloter la decision jouee. Les PNJ continuent d'utiliser les
heuristiques locales.

Tester la connectivite OpenRouter :

```sh
GAME_SIMULATOR_LLM_API_KEY=replace-with-your-key mix llm.shadow_ping
```

Les resultats sont ecrits en NDJSON dans `GAME_SIMULATOR_LLM_AUDIT_FILE`.
Ne versionnez pas ce fichier : il peut contenir du contexte de main et des
donnees utiles pour l'analyse.

### Release

Construire et demarrer une release :

```sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile_front
MIX_ENV=prod mix release
_build/prod/rel/game_simulator/bin/game_simulator start
```

Avec un fichier de configuration externe :

```sh
GAME_SIMULATOR_ENV_FILE=/etc/game_simulator/game_simulator.env \
  _build/prod/rel/game_simulator/bin/game_simulator start
```

Pour un deploiement gere, injectez les variables `GAME_SIMULATOR_*` depuis le
process manager, la plateforme container ou le gestionnaire de secrets.

### Exposer avec HAProxy

Pour exposer l'application depuis une machine publique, vous pouvez laisser
Game Simulator ecouter en local sur `127.0.0.1:4000` et placer HAProxy devant.
HAProxy peut alors gerer le port public, le TLS et le routage vers l'application.

Exemple minimal de backend :

```haproxy
backend game_simulator
  server app 127.0.0.1:4000 check
```

Exposez uniquement via HTTPS si l'application sort de votre machine locale, et
gardez `.env`, SQLite, les secrets de token et les audits hors du repertoire
servi publiquement.

## Documentation developpeur

### Organisation du projet

- `lib/game_simulator/` : supervision, configuration et gestion des tables.
- `lib/game_simulator_web/` : endpoint HTTP, authentification et utilisateurs.
- `lib/poker/` : moteur de jeu, profils PNJ, decisions et audit LLM.
- `web/` : sources HTML, CSS, JavaScript et assets du client.
- `scripts/` : scripts d'analyse et de simulation.
- `test/` : tests unitaires et tests d'endpoint.

Au demarrage, `GameSimulator.Application` valide la configuration, cree les
dossiers de logs/donnees, demarre le registre des tables, le superviseur de
tables et, si active, le serveur HTTP.

### Commandes de developpement

```sh
mix deps.get
mix test
mix compile_front
mix run --no-halt
```

Pour lancer le serveur sur un autre port sans modifier `.env` :

```sh
GAME_SIMULATOR_PORT=4100 GAME_SIMULATOR_LOG_LEVEL=info mix run --no-halt
```

Pour inspecter les profils PNJ sur un gros echantillon :

```sh
mix run --no-start scripts/poker_profile_stats.exs 10000
```

Le script lance une table de six PNJ, joue le nombre de mains demande, remet les
stacks a `200` entre les mains et imprime des tableaux Markdown par siege et par
archetype. Les metriques incluent VPIP, PFR, limp, 3bet, preflop fold, c-bet,
fold vs c-bet, WTSD et W$SD.

### API HTTP

Les routes JSON disponibles sont :

| Route | Comportement |
| --- | --- |
| `POST /api/auth/register` | Retourne `501 not_implemented`. |
| `POST /api/auth/login` | Accepte `{ "user", "password" }` et retourne un token signe. |
| `POST /api/auth/refresh` | Retourne `501 not_implemented`. |
| `POST /api/auth/logout` | Retourne `204`; le client supprime son token stateless. |
| `GET /api/auth/me` | Requiert `Authorization: Bearer <token>` et retourne l'utilisateur et ses permissions effectives. |
| `POST /api/auth/password` | Change le mot de passe de l'utilisateur authentifie. |
| `GET /api/admin/users` | Liste les utilisateurs ; permission `admin` requise. |
| `POST /api/admin/users` | Cree un utilisateur ; permission `admin` requise. |
| `PUT /api/admin/users/:user` | Met a jour les permissions et reset optionnellement le mot de passe ; permission `admin` requise. |
| `DELETE /api/admin/users/:user` | Supprime un utilisateur ; permission `admin` requise. |
| `POST /api/table` | Cree ou recupere la table temporaire de l'utilisateur. |
| `GET /api/table` | Retourne l'etat de la table. |
| `GET /api/table/extract?n=10` | Exporte les mains recentes en Markdown, de 1 a 50 mains. |
| `POST /api/table/action` | Joue `fold`, `check`, `call`, `all_in`, `bet` ou `raise_to`. |
| `POST /api/table/advance-bot` | Avance exactement une action PNJ quand un bot doit agir. |
| `POST /api/table/next-hand` | Lance la main suivante apres une main terminee. |
| `POST /api/table/llm-mode` | Change le mode LLM de la table courante : `llm`, `shadow` ou `off`. |
| `DELETE /api/table` | Arrete la table temporaire de l'utilisateur. |

Les routes de table ne font pas confiance a un identifiant fourni par le
navigateur : l'utilisateur vient toujours du token verifie. Les actions et les
montants recus sont revalides par le moteur de jeu.

### Poker et PNJ

Le moteur gere l'ordre de parole, les actions legales, les calls all-in, les
relances all-in incompletes qui ne rouvrent pas l'action, le deroulement
automatique du board, les side pots, les split pots et les jetons impairs.

Les decisions PNJ sont locales et heuristiques. Les profils sont orientes NL2 :
`calling_station`, `limp_caller`, `fit_or_fold`, `nit_weak`, `tag`, `lag` et
`spewy_aggro`.

Les decisions tiennent compte du prix a payer, des pot odds, du sizing, de la
pression de stack, des situations preflop larges et de categories postflop
simples. Les mains faites avec cartes privees sont distinguees des mains surtout
composees par le board.

### Client web

`html_handler` est epingle au commit `3fa137885b3f68915574c1d476d7eedf5e77aadc`
de [`gregoire-riviere/html_handler`](https://github.com/gregoire-riviere/html_handler).

Le client est servi par `HTMLHandler.Plug.OutputStatic` depuis `priv/static/`.
Le SSR n'est pas active. Relancez `mix compile_front` apres une modification
HTML, CSS ou JavaScript. Le dossier genere `priv/static/` n'est pas versionne.

### Securite

L'API utilise des tokens signes par `HTMLHandler.Token`. Le secret est stocke
dans `GAME_SIMULATOR_DATA_DIR/token.secret`.

Gardez `game_simulator.sqlite3`, `token.secret`, `.env` et les fichiers d'audit
hors du depot. En production, preferez des variables d'environnement ou un
gestionnaire de secrets pour les valeurs sensibles.

L'API generique de token fournie par `html_handler` est desactivee : elle accepte
un identifiant arbitraire. Toute nouvelle source d'identite doit authentifier
l'utilisateur cote serveur puis appeler `GameSimulatorWeb.Auth.issue_token/1`.
