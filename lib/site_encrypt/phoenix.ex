# I find this module needlessly confusing because it is both a process that is
# started (and then starts your endpoint), as well as the holder of the macros
# that extend your endpoint through `use`
defmodule SiteEncrypt.Phoenix do
  @moduledoc """
  `SiteEncrypt` adapter for Phoenix endpoints.

  ## Usage

  1. Add `use SiteEncrypt.Phoenix` to your endpoint immediately after `use Phoenix.Endpoint`
  2. Configure https via `configure_https/2`.
  3. Add the implementation of `c:SiteEncrypt.certification/0` to the endpoint (the
    `@behaviour SiteEncrypt` is injected when this module is used).
  4. Start the endpoint by providing `{SiteEncrypt.Phoenix, PhoenixDemo.Endpoint}` as a supervisor child.
  """

  use SiteEncrypt.Adapter
  alias SiteEncrypt.Adapter

  @spec child_spec(endpoint :: module) :: Supervisor.child_spec()

  @doc "Starts the endpoint managed by `SiteEncrypt`."
  @spec start_link({endpoint :: module, impl_module :: module}) :: Supervisor.on_start()
  def start_link({endpoint, impl_module}),
    do: Adapter.start_link(__MODULE__, {endpoint, impl_module})

  @doc """
  Merges paths to key and certificates to the `:https` configuration of the endpoint config.

  Invoke this macro from `c:Phoenix.Endpoint.init/2` to complete the https configuration:

      defmodule MyEndpoint do
        # ...

        @impl Phoenix.Endpoint
        def init(_key, config) do
          # this will merge key, cert, and chain into `:https` configuration from config.exs
          {:ok, SiteEncrypt.Phoenix.configure_https(config)}

          # to completely configure https from `init/2`, invoke:
          #   SiteEncrypt.Phoenix.configure_https(config, port: 4001, ...)
        end

        # ...
      end

  The `options` are any valid adapter HTTPS options. For many great tips on configuring HTTPS for
  production refer to the [Plug HTTPS guide](https://hexdocs.pm/plug/https.html#content).
  """
  # TODO: I think this can be changed to a function
  # defmacro configure_https(config, module, https_opts \\ []) do
  #   quote bind_quoted: [config: config, module: module, https_opts: https_opts] do
  #     https_config =
  #       (Keyword.get(config, :https) || [])
  #       |> Config.Reader.merge(https_opts)
  #       |> Config.Reader.merge(SiteEncrypt.https_keys(module))

  #     Keyword.put(config, :https, https_config)
  #   end
  # end
  def configure_https(config, module, https_opts \\ []) do
    https_config =
      (Keyword.get(config, :https) || [])
      |> Config.Reader.merge(https_opts)
      |> Config.Reader.merge(SiteEncrypt.https_keys(module))

    Keyword.put(config, :https, https_config)
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      unless Enum.member?(@behaviour, Phoenix.Endpoint),
        do: raise("SiteEncrypt.Phoenix must be used after Phoenix.Endpoint")

      @behaviour SiteEncrypt
      require SiteEncrypt
      require SiteEncrypt.Phoenix

      plug SiteEncrypt.AcmeChallenge, __MODULE__

      @impl SiteEncrypt
      def handle_new_cert, do: :ok

      defoverridable handle_new_cert: 0
    end
  end

  @impl Adapter
  def config(_id, endpoint, impl_module) do
    %{
      certification: impl_module.certification(),
      site_spec: endpoint.child_spec([])
    }
  end

  @impl Adapter
  def http_port(_id, endpoint) do
    if server?(endpoint),
      do: Keyword.fetch(endpoint.config(:http), :port),
      else: :error
  end

  defp server?(endpoint) do
    endpoint.config(:server) ||
      Application.get_env(:phoenix, :serve_endpoints, false)
  end
end
