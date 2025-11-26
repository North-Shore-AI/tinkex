import Config

config :tinkex, :enable_http_pools, true

# Configure Nx to use EXLA backend for accelerated tensor operations
config :nx, :default_backend, EXLA.Backend

# Configure EXLA client (host = CPU, cuda = GPU)
config :exla, :default_client, :host

import_config "#{config_env()}.exs"
