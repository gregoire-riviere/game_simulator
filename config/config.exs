import Config

config :game_simulator, environment: config_env()

config :game_simulator,
  start_http?: true

config :html_handler,
  directories: %{
    html: "web",
    css: "web/assets/css",
    js: "web/assets/js",
    dir_to_copy: [],
    output: "priv/static"
  },
  templatization?: false,
  watch?: false,
  seo?: false,
  routes: %{"/" => "index.html"}

import_config "#{config_env()}.exs"
