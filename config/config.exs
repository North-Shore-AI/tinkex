import Config

config :tinkex, :enable_http_pools, false

import_config "#{config_env()}.exs"
