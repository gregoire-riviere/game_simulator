# GameSimulator

GameSimulator is an Elixir application intended to run locally during development
and as a Mix release in production. It currently configures its HTTP server
parameters but does not start Cowboy until an HTTP API is added.

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
| `GAME_SIMULATOR_TOKEN_TTL_SECONDS` | `3600` | `3600` | Signed token lifetime in seconds; must be greater than zero. |
| `GAME_SIMULATOR_LLM_API_KEY` | unset | unset | Optional LLM key; it is required only by future LLM calls. |
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
GAME_SIMULATOR_TOKEN_TTL_SECONDS=3600
GAME_SIMULATOR_LLM_API_KEY=replace-with-your-key
```

Override a local file from the shell without editing it:

```sh
GAME_SIMULATOR_PORT=4100 GAME_SIMULATOR_LOG_LEVEL=info mix run --no-halt
```

## Client and authentication API

`html_handler` is pinned to commit `3fa137885b3f68915574c1d476d7eedf5e77aadc`
of [`gregoire-riviere/html_handler`](https://github.com/gregoire-riviere/html_handler).
It compiles the static interface in `web/` and serves it through Cowboy. SSR is
not enabled.

The following JSON routes are reserved for the authentication provider:

| Route | Current behavior |
| --- | --- |
| `POST /api/auth/register` | Returns `501 not_implemented`. |
| `POST /api/auth/login` | Returns `501 not_implemented`. |
| `POST /api/auth/refresh` | Returns `501 not_implemented`. |
| `POST /api/auth/logout` | Returns `501 not_implemented`. |
| `GET /api/auth/me` | Requires `Authorization: Bearer <token>` and returns the token subject and expiration. |

Tokens are signed and verified with `HTMLHandler.Token`; the signing secret is
stored in `GAME_SIMULATOR_DATA_DIR/token.secret`. The generic token issuance API
from `html_handler` is deliberately disabled because it accepts an arbitrary
user identifier. A future credential provider must authenticate the user first,
then call `GameSimulatorWeb.Auth.issue_token/1` on the server.

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
