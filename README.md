# GameSimulator

GameSimulator is an Elixir application intended to run locally during development
and as a Mix release in production. It serves a small browser client and a JSON
API for authentication and the current poker table.

## Prerequisites

- Elixir `~> 1.19` and a compatible Erlang/OTP runtime
- `mix` and Hex (`mix local.hex` when needed)

## Local installation and startup

```sh
git clone <repository-url> game_simulator
cd game_simulator
mix deps.get
cp .env.example .env
mix install_minifiers
mix compile_front
mix run --no-halt
```

`.env` is optional: all settings have development defaults. It is ignored by Git;
commit only `.env.example`. Use `.env.test` for test-specific local overrides.

Run the test suite with:

```sh
mix test
```

The client sources live in `web/`. Run `mix compile_front` after modifying HTML,
CSS, or JavaScript; the generated `priv/static/` directory is intentionally not
versioned. `mix install_minifiers` installs the `html-minifier`, `minify`, and
`uglify-js` tools used by `html_handler`.

## Configuration

Configuration is resolved at startup, so it works identically with `mix` and a
release. Values are selected in this order:

1. System environment variables.
2. The dotenv file selected by `GAME_SIMULATOR_ENV_FILE`.
3. The default dotenv file: `.env` for development and releases, `.env.test` for tests.
4. Built-in defaults.

For a release, the default `.env` location is the release root. Set
`GAME_SIMULATOR_ENV_FILE` to an absolute path when configuration is managed
outside the release directory. System variables always override file values.

| Variable | Default in dev/test | Default in production | Description |
| --- | --- | --- | --- |
| `GAME_SIMULATOR_HOST` | `127.0.0.1` | `0.0.0.0` | Interface reserved for the future HTTP server. |
| `GAME_SIMULATOR_PORT` | `4000` | `4000` | Future HTTP server port; must be between 1 and 65535. |
| `GAME_SIMULATOR_LOG_DIR` | `<project>/log` / temporary test directory | `<release>/log` | Directory containing `info.log` and `debug.log`. Relative paths are resolved from the project or release root. |
| `GAME_SIMULATOR_LOG_LEVEL` | `debug` | `debug` | Console threshold: `debug`, `info`, `warning`, or `error`. |
| `GAME_SIMULATOR_DATA_DIR` | `<project>/data` / temporary test directory | `<release>/data` | Persistent token-signing secret directory. Mount or back up this directory in production. |
| `GAME_SIMULATOR_USERS_FILE` | `<data-dir>/users` | `<data-dir>/users` | Local user file. Use an absolute path or a path relative to the project/release root. Keep it outside the repository and restrict its permissions. |
| `GAME_SIMULATOR_TOKEN_TTL_SECONDS` | `3600` | `3600` | Signed token lifetime in seconds; must be greater than zero. |
| `GAME_SIMULATOR_LLM_ENABLED` | `false` | `false` | Enables LLM shadow decisions when set to `true`. |
| `GAME_SIMULATOR_LLM_SHADOW_MODE` | `true` | `true` | Keeps LLM decisions observational only. |
| `GAME_SIMULATOR_LLM_PROVIDER` | `openrouter` | `openrouter` | LLM provider for shadow decisions. |
| `GAME_SIMULATOR_LLM_API_KEY` | unset | unset | OpenRouter API key; required only when LLM calls are enabled or when running the ping task. |
| `GAME_SIMULATOR_LLM_BASE_URL` | `https://openrouter.ai/api/v1` | same | OpenRouter-compatible API base URL. |
| `GAME_SIMULATOR_LLM_DECISION_MODEL` | `google/gemini-2.5-flash` | same | Model used for shadow decisions. |
| `GAME_SIMULATOR_LLM_TIMEOUT_MS` | `1500` | `1500` | Maximum wait for a shadow decision. |
| `GAME_SIMULATOR_LLM_INTEREST_THRESHOLD` | `4` | `4` | Minimum spot-interest score before calling the LLM. |
| `GAME_SIMULATOR_LLM_AUDIT_FILE` | `data/llm_shadow_audit.ndjson` | same | NDJSON audit file for shadow decisions. |
| `GAME_SIMULATOR_LLM_HTTP_REFERER` | unset | unset | Optional OpenRouter referer header. |
| `GAME_SIMULATOR_LLM_X_TITLE` | `game_simulator` | same | Optional OpenRouter title header. |
| `GAME_SIMULATOR_ENV_FILE` | environment-specific default | `<release>/.env` | Optional path to a dotenv file. |

`debug.log` always retains every application log event. `info.log` retains
`:info`, `:warning`, and `:error` events. The configured log level controls
console output only.

Example `.env`:

```dotenv
GAME_SIMULATOR_HOST=127.0.0.1
GAME_SIMULATOR_PORT=4000
GAME_SIMULATOR_LOG_DIR=log
GAME_SIMULATOR_LOG_LEVEL=debug
GAME_SIMULATOR_DATA_DIR=data
GAME_SIMULATOR_USERS_FILE=data/users
GAME_SIMULATOR_TOKEN_TTL_SECONDS=3600
GAME_SIMULATOR_LLM_ENABLED=false
GAME_SIMULATOR_LLM_SHADOW_MODE=true
GAME_SIMULATOR_LLM_API_KEY=replace-with-your-key
```

Override a local file from the shell without editing it:

```sh
GAME_SIMULATOR_PORT=4100 GAME_SIMULATOR_LOG_LEVEL=info mix run --no-halt
```

Test OpenRouter connectivity without starting a poker hand:

```sh
GAME_SIMULATOR_LLM_API_KEY=replace-with-your-key mix llm.shadow_ping
```

## Client and authentication API

`html_handler` is pinned to commit `3fa137885b3f68915574c1d476d7eedf5e77aadc`
of [`gregoire-riviere/html_handler`](https://github.com/gregoire-riviere/html_handler).
It compiles the static interface in `web/` and serves it through Cowboy. SSR is
not enabled.

The browser interface is available at `/` when `GAME_SIMULATOR_HOST` and
`GAME_SIMULATOR_PORT` are configured. Create its first user from IEx; passwords
must contain at least 12 characters. The function hashes the password with
PBKDF2-HMAC-SHA256 and appends only the username, parameters, salt, and hash to
the configured `GAME_SIMULATOR_USERS_FILE`.

```sh
mix run -e 'IO.inspect(GameSimulatorWeb.Users.add("admin", "a-long-unique-password"))'
```

Do not commit this file or expose it through the web server. Use a separate
secret manager or user provider when local file management is no longer suitable.

The following JSON routes are available:

| Route | Current behavior |
| --- | --- |
| `POST /api/auth/register` | Returns `501 not_implemented`. |
| `POST /api/auth/login` | Accepts JSON `{ "user", "password" }` and returns a signed token on success. |
| `POST /api/auth/refresh` | Returns `501 not_implemented`. |
| `POST /api/auth/logout` | Returns `204`; the browser removes the stateless token. |
| `GET /api/auth/me` | Requires `Authorization: Bearer <token>` and returns the token subject and expiration. |
| `POST /api/table` | Creates or returns the authenticated user's temporary poker table. |
| `GET /api/table` | Returns the authenticated user's table state. |
| `GET /api/table/extract?n=10` | Exports recent hands as Markdown, from 1 to 50 hands. |
| `POST /api/table/action` | Plays a hero action: `fold`, `check`, `call`, `all_in`, `bet`, or `raise_to`. |
| `POST /api/table/advance-bot` | Advances exactly one PNJ action when a bot is active. |
| `POST /api/table/next-hand` | Starts the next hand after the previous one is finished. |
| `DELETE /api/table` | Stops the authenticated user's temporary table. |

Tokens are signed and verified with `HTMLHandler.Token`; the signing secret is
stored in `GAME_SIMULATOR_DATA_DIR/token.secret`. The generic token issuance API
from `html_handler` is deliberately disabled because it accepts an arbitrary
user identifier. A future credential provider must authenticate the user first,
then call `GameSimulatorWeb.Auth.issue_token/1` on the server.

## Poker mode

The current poker implementation targets a simple NL2 6-max cash table:

- blinds are `1/2`, represented as integer cents;
- every player starts with `200`;
- the hero sits at seat 6 and five PNJ fill seats 1 to 5;
- `mode: :cash_nl2` automatically tops up stacks below `80` back to `200`;
- the interface shows automatic top-ups in the recent actions list.

The rules engine handles betting order, legal check/call/fold/bet/raise actions,
all-in calls, incomplete all-in raises that do not reopen raises to players who
already acted, automatic board rollout when nobody can act, side pots, split pots,
and odd chips.

PNJ decisions are local heuristics, not LLM calls. Their profiles are weighted
toward NL2 patterns such as `calling_station`, `limp_caller`, `fit_or_fold`,
`nit_weak`, `tag`, `lag`, and `spewy_aggro`. Decisions use the current price to
call (`to_call`, pot odds, bet size, and stack pressure), broad preflop situations
such as limp/raise/all-in, simple preflop sizing rules, and postflop categories
that distinguish made hands using private cards from hands mostly on the board.

Rake is intentionally not enabled in this V1.

### PNJ profile simulation

Run a bot-only simulation to inspect whether local PNJ profiles look plausible
over a larger sample:

```sh
mix run --no-start scripts/poker_profile_stats.exs 10000
```

The script creates a six-PNJ table, plays the requested number of hands, resets
all stacks to `200` between hands, and prints Markdown tables per seat and per
archetype. It reports VPIP, PFR, limp, 3bet, preflop fold, c-bet, fold vs c-bet,
WTSD, and W$SD.

The metrics are heuristic but stable enough for tuning:

- VPIP excludes posted blinds and counts voluntary preflop chips.
- PFR counts preflop aggressive actions.
- Limp counts a voluntary preflop call before a raise.
- C-bet counts the preflop aggressor making the first flop bet.
- 3bet is measured over 3bet opportunities; the report also prints the opportunity count.
- WTSD counts non-folded hands reaching a five-card board, divided by flops seen.
- W$SD counts showdown hands with positive profit.

## Release

Build and start a release:

```sh
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix compile_front
MIX_ENV=prod mix release
_build/prod/rel/game_simulator/bin/game_simulator start
```

For an external configuration file, provide its path at startup:

```sh
GAME_SIMULATOR_ENV_FILE=/etc/game_simulator/game_simulator.env \
  _build/prod/rel/game_simulator/bin/game_simulator start
```

For managed deployments, inject `GAME_SIMULATOR_*` variables through the process
manager, container platform, or secret manager. This is preferred for secrets
because it avoids placing credentials in the release filesystem.
