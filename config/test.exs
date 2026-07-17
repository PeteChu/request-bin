import Config
config :request_bin, Oban, testing: :manual

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
database_options =
  case System.get_env("TEST_DATABASE_URL") do
    nil ->
      [
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
        database: "request_bin_test#{System.get_env("MIX_TEST_PARTITION")}"
      ]

    url ->
      uri = URI.parse(url)

      if uri.path in [nil, "", "/"] do
        raise ArgumentError, "TEST_DATABASE_URL must include a database name"
      end

      uri =
        case System.get_env("MIX_TEST_PARTITION") do
          partition when partition in [nil, ""] -> uri
          partition -> %{uri | path: uri.path <> partition}
        end

      [url: URI.to_string(uri)]
  end

repo_options =
  database_options ++
    [pool: Ecto.Adapters.SQL.Sandbox, pool_size: System.schedulers_online() * 2]

config :request_bin, RequestBin.Repo, repo_options

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :request_bin, RequestBinWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test_secret_key_base_", 4),
  server: false

# In test we don't send emails
config :request_bin, RequestBin.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust URL comparisons
config :phoenix,
  sort_verified_routes_query_params: true
