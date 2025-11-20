import Config

config :tinkex, :enable_http_pools, true

import_config "#{config_env()}.exs"
