# Game Simulator

[Version francaise](README.md)

Game Simulator is an Elixir application that exposes a local web interface and a
JSON API to play poker hands against NPCs. It can run in development with `mix`
or in production as a Mix release.

The project currently includes:

- a Plug/Cowboy HTTP server;
- a static interface compiled from `web/` to `priv/static/`;
- local SQLite authentication with permissions and signed tokens;
- one temporary table per authenticated user;
- an NL2 6-max poker engine with heuristic NPCs;
- an optional LLM shadow mode to audit decisions without changing gameplay.

## Table of contents

- [User documentation](#user-documentation)
  - [Prerequisites](#prerequisites)
  - [Installation and startup](#installation-and-startup)
  - [Create a user](#create-a-user)
  - [Play](#play)
  - [Configure the application](#configure-the-application)
  - [LLM shadow mode](#llm-shadow-mode)
  - [Release](#release)
  - [Expose with HAProxy](#expose-with-haproxy)
- [Developer documentation](#developer-documentation)
  - [Project layout](#project-layout)
  - [Development commands](#development-commands)
  - [HTTP API](#http-api)
  - [Poker and NPCs](#poker-and-npcs)
  - [Web client](#web-client)
  - [Security](#security)

## User documentation

### Prerequisites

- Elixir `~> 1.19` with a compatible Erlang/OTP version.
- `mix` and Hex (`mix local.hex` if needed).
- The minification tools installed by `mix install_minifiers` to compile the web
  client.

### Installation and startup

```sh
git clone <repository-url> game_simulator
cd game_simulator
mix deps.get
cp .env.example .env
mix install_minifiers
mix compile_front
mix run --no-halt
```

By default, the server listens on `http://127.0.0.1:4000`.

`.env` is optional in development: built-in defaults already exist. The file is
ignored by Git; only commit `.env.example`.

### Create a user

Users are currently created from the server. Passwords must contain at least 12
characters.

```sh
mix run -e 'IO.inspect(GameSimulatorWeb.Users.add("admin", "a-long-unique-password", ["admin"]))'
```

Users are stored in the SQLite `users` table. Valid permissions are `admin`,
`poker`, and `llm`; `admin` grants access to everything. If an old
`GAME_SIMULATOR_USERS_FILE` exists on first startup, its accounts are imported
once as admins.

After 5 consecutive failed login attempts, the account is locked for 12 hours,
including admin accounts. An admin can unlock it from the administration UI, or
from the console:

```sh
mix run -e 'IO.inspect(GameSimulatorWeb.Users.unlock("admin"))'
```

### Play

Once the server is running, open `http://127.0.0.1:4000`, sign in, then start a
table from the interface.

The current mode targets a simplified NL2 6-max cash-game table:

- blinds are `1/2`, represented as integer cents;
- each player starts with a `200` stack;
- the hero sits at seat 6, with five NPCs in seats 1 to 5;
- stacks below `80` are automatically topped up to `200`;
- rake is not enabled in this V1.

NPCs use local heuristics, not LLM calls.

### Configure the application

Configuration is resolved at startup, with the same behavior under `mix` and in
a release. Priority order is:

1. System environment variables.
2. The file pointed to by `GAME_SIMULATOR_ENV_FILE`.
3. The default file: `.env` in development/release, `.env.test` in tests.
4. Built-in defaults.

In a release, the default `.env` is read from the release root. If configuration
is managed elsewhere, set `GAME_SIMULATOR_ENV_FILE` to an absolute path. System
variables always take priority.

| Variable | Dev/test | Production | Description |
| --- | --- | --- | --- |
| `GAME_SIMULATOR_HOST` | `127.0.0.1` | `0.0.0.0` | HTTP listen interface. Must be an IP address. |
| `GAME_SIMULATOR_PORT` | `4000` | `4000` | HTTP port, between 1 and 65535. |
| `GAME_SIMULATOR_LOG_DIR` | `<project>/log` / temporary test directory | `<release>/log` | Directory containing `info.log` and `debug.log`. |
| `GAME_SIMULATOR_LOG_LEVEL` | `debug` | `debug` | Console threshold: `debug`, `info`, `warning`, or `error`. |
| `GAME_SIMULATOR_DATA_DIR` | `<project>/data` / temporary test directory | `<release>/data` | Local data, including SQLite and the token signing secret. |
| `GAME_SIMULATOR_USERS_FILE` | `<data-dir>/users` | `<data-dir>/users` | Optional legacy import path for the old user file. |
| `GAME_SIMULATOR_TOKEN_TTL_SECONDS` | `86400` | `86400` | Signed token lifetime, in seconds. |
| `GAME_SIMULATOR_LLM_ENABLED` | `false` | `false` | Enables LLM shadow decision calls. |
| `GAME_SIMULATOR_LLM_SHADOW_MODE` | `true` | `true` | Keeps LLM decisions observational only. |
| `GAME_SIMULATOR_LLM_PROVIDER` | `openrouter` | `openrouter` | Supported LLM provider. |
| `GAME_SIMULATOR_LLM_API_KEY` | unset | unset | OpenRouter key, required when LLM calls are enabled. |
| `GAME_SIMULATOR_LLM_BASE_URL` | `https://openrouter.ai/api/v1` | same | OpenRouter-compatible URL. Must use HTTPS. |
| `GAME_SIMULATOR_LLM_DECISION_MODEL` | `google/gemini-2.5-flash` | same | Model used for shadow decisions. |
| `GAME_SIMULATOR_LLM_TIMEOUT_MS` | `1500` | `1500` | Maximum LLM call timeout. |
| `GAME_SIMULATOR_LLM_INTEREST_THRESHOLD` | `4` | `4` | Minimum score before calling the LLM. |
| `GAME_SIMULATOR_LLM_AUDIT_FILE` | `data/llm_shadow_audit.ndjson` | same | NDJSON shadow decision log. |
| `GAME_SIMULATOR_LLM_HTTP_REFERER` | unset | unset | Optional OpenRouter header. |
| `GAME_SIMULATOR_LLM_X_TITLE` | `game_simulator` | same | Optional OpenRouter header. |
| `GAME_SIMULATOR_ENV_FILE` | environment-specific | `<release>/.env` | Optional dotenv file. |

Relative paths are resolved from the project or release root. `debug.log` keeps
all application events. `info.log` keeps `:info`, `:warning`, and `:error`
events. The configured level only affects console output.

Minimal example:

```dotenv
GAME_SIMULATOR_HOST=127.0.0.1
GAME_SIMULATOR_PORT=4000
GAME_SIMULATOR_LOG_DIR=log
GAME_SIMULATOR_LOG_LEVEL=debug
GAME_SIMULATOR_DATA_DIR=data
GAME_SIMULATOR_TOKEN_TTL_SECONDS=86400
GAME_SIMULATOR_LLM_ENABLED=false
```

### LLM shadow mode

LLM shadow mode is optional. When enabled, it audits selected interesting spots
without driving the played decision. NPCs keep using local heuristics.

Test OpenRouter connectivity:

```sh
GAME_SIMULATOR_LLM_API_KEY=replace-with-your-key mix llm.shadow_ping
```

Results are written as NDJSON to `GAME_SIMULATOR_LLM_AUDIT_FILE`. Do not version
this file: it may contain hand context and data useful for analysis.

### Release

Build and start a release:

```sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile_front
MIX_ENV=prod mix release
_build/prod/rel/game_simulator/bin/game_simulator start
```

With an external configuration file:

```sh
GAME_SIMULATOR_ENV_FILE=/etc/game_simulator/game_simulator.env \
  _build/prod/rel/game_simulator/bin/game_simulator start
```

For managed deployments, inject `GAME_SIMULATOR_*` variables from the process
manager, container platform, or secret manager.

### Expose with HAProxy

To expose the application from a public machine, you can keep Game Simulator
listening locally on `127.0.0.1:4000` and put HAProxy in front of it. HAProxy can
then handle the public port, TLS, and routing to the application.

Minimal backend example:

```haproxy
backend game_simulator
  server app 127.0.0.1:4000 check
```

Expose through HTTPS only if the application leaves your local machine, and keep
`.env`, SQLite, token secrets, and audit files outside the publicly served
directory.

## Developer documentation

### Project layout

- `lib/game_simulator/`: supervision, configuration, and table management.
- `lib/game_simulator_web/`: HTTP endpoint, authentication, and users.
- `lib/poker/`: game engine, NPC profiles, decisions, and LLM audit.
- `web/`: HTML, CSS, JavaScript, and asset sources for the client.
- `scripts/`: analysis and simulation scripts.
- `test/`: unit and endpoint tests.

At startup, `GameSimulator.Application` validates configuration, creates log and
data directories, starts the table registry, the table supervisor, and the HTTP
server when enabled.

### Development commands

```sh
mix deps.get
mix test
mix compile_front
mix run --no-halt
```

Run the server on another port without editing `.env`:

```sh
GAME_SIMULATOR_PORT=4100 GAME_SIMULATOR_LOG_LEVEL=info mix run --no-halt
```

Inspect NPC profiles on a larger sample:

```sh
mix run --no-start scripts/poker_profile_stats.exs 10000
```

The script starts a six-NPC table, plays the requested number of hands, resets
all stacks to `200` between hands, and prints Markdown tables by seat and
archetype. Metrics include VPIP, PFR, limp, 3bet, preflop fold, c-bet, fold vs
c-bet, WTSD, and W$SD.

### HTTP API

Available JSON routes:

| Route | Behavior |
| --- | --- |
| `POST /api/auth/register` | Returns `501 not_implemented`. |
| `POST /api/auth/login` | Accepts `{ "user", "password" }` and returns a signed token. |
| `POST /api/auth/refresh` | Returns `501 not_implemented`. |
| `POST /api/auth/logout` | Returns `204`; the client deletes its stateless token. |
| `GET /api/auth/me` | Requires `Authorization: Bearer <token>` and returns the user and effective permissions. |
| `POST /api/auth/password` | Changes the authenticated user's password. |
| `GET /api/admin/users` | Lists users; requires `admin`. |
| `POST /api/admin/users` | Creates a user; requires `admin`. |
| `PUT /api/admin/users/:user` | Updates permissions and optionally resets the password; requires `admin`. |
| `DELETE /api/admin/users/:user` | Deletes a user; requires `admin`. |
| `POST /api/table` | Creates or returns the user's temporary table. |
| `GET /api/table` | Returns the table state. |
| `GET /api/table/extract?n=10` | Exports recent hands as Markdown, from 1 to 50 hands. |
| `POST /api/table/action` | Plays `fold`, `check`, `call`, `all_in`, `bet`, or `raise_to`. |
| `POST /api/table/advance-bot` | Advances exactly one NPC action when a bot must act. |
| `POST /api/table/next-hand` | Starts the next hand after a finished hand. |
| `POST /api/table/llm-mode` | Changes the current table LLM mode: `llm`, `shadow`, or `off`. |
| `DELETE /api/table` | Stops the user's temporary table. |

Table routes do not trust any user identifier provided by the browser: the user
always comes from the verified token. Actions and amounts received from the
client are revalidated by the game engine.

### Poker and NPCs

The engine handles action order, legal actions, all-in calls, incomplete all-in
raises that do not reopen action, automatic board rollout, side pots, split pots,
and odd chips.

NPC decisions are local and heuristic. Profiles are NL2-oriented:
`calling_station`, `limp_caller`, `fit_or_fold`, `nit_weak`, `tag`, `lag`, and
`spewy_aggro`.

Decisions account for the price to call, pot odds, sizing, stack pressure, broad
preflop situations, and simple postflop categories. Made hands using private
cards are distinguished from hands mostly made by the board.

### Web client

`html_handler` is pinned to commit `3fa137885b3f68915574c1d476d7eedf5e77aadc`
from [`gregoire-riviere/html_handler`](https://github.com/gregoire-riviere/html_handler).

The client is served by `HTMLHandler.Plug.OutputStatic` from `priv/static`. SSR
is not enabled. Run `mix compile_front` after changing HTML, CSS, or JavaScript.
The generated `priv/static/` directory is not versioned.

### Security

The API uses tokens signed by `HTMLHandler.Token`. The secret is stored in
`GAME_SIMULATOR_DATA_DIR/token.secret`.

Keep `game_simulator.sqlite3`, `token.secret`, `.env`, and audit files out of the
repository. In production, prefer environment variables or a secret manager for
sensitive values.

The generic token API provided by `html_handler` is disabled: it accepts an
arbitrary user identifier. Any future identity source must authenticate the user
server-side, then call `GameSimulatorWeb.Auth.issue_token/1`.
