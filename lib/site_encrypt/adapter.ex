# The adapter implementation needs to define what module it will start
# And not just implicitly based on an "id"
defmodule SiteEncrypt.Adapter do
  alias SiteEncrypt.{Acme, Registry}

  use Parent.GenServer

  @callback config(SiteEncrypt.id(), arg :: any, impl_module :: module) :: %{
              certification: SiteEncrypt.certification(),
              site_spec: Parent.child_spec()
            }

  @callback http_port(SiteEncrypt.id(), arg :: any) :: {:ok, pos_integer} | :error

  defmodule State do
    defstruct [:callback, :id, :arg, :impl_module]

    @type t :: %__MODULE__{
      # The identifier for an instance of the adapter
      # This is what is stored in the configuration registry
      id: any,
      # Argument that is specific to the adapter implementation
      # The Phoenix adapter expects this to be the endpoint
      arg: any,
      # The module that implements SiteEncrypt.Behaviour
      impl_module: module
    }
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour SiteEncrypt.Adapter

      @doc """
      Returns a specification to start this module under a supervisor.

      See `Supervisor`.
      """
      def child_spec(start_opts) do
        Supervisor.child_spec(
          %{
            id: __MODULE__,
            type: :supervisor,
            start: {__MODULE__, :start_link, [start_opts]}
          },
          unquote(opts)
        )
      end
    end
  end

  # Callback here should be called callback_module
  def start_link(callback, {id, impl_module}),
    do: Parent.GenServer.start_link(__MODULE__, {callback, id, impl_module}, name: Registry.root(id))

  @doc false
  # used only in tests
  def restart_site(id, fun) do
    Parent.Client.shutdown_all(Registry.root(id))
    fun.()
    GenServer.call(Registry.root(id), :start_all_children)
  end

  @impl GenServer
  def init({callback, id, arg}) do
    state = %State{callback: callback, id: id, arg: id, impl_module: arg}
    start_all_children!(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:start_all_children, _from, state) do
    start_all_children!(state)
    {:reply, :ok, state}
  end

  defp start_all_children!(%State{arg: arg, id: id, impl_module: impl_module} = state) do
    adapter_config = state.callback.config(id, arg, impl_module)
    # Can we store this config earlier????
    Registry.store_config(id, adapter_config.certification)

    SiteEncrypt.initialize_certs(adapter_config.certification)

    Parent.start_all_children!([
      Parent.child_spec(adapter_config.site_spec, id: :site),
      Parent.child_spec(Acme.Server,
        start: fn -> start_acme_server(state, adapter_config) end,
        binds_to: [:site]
      )
      | SiteEncrypt.Certification.child_specs(id)
    ])
  end

  defp start_acme_server(%State{} = state, adapter_config) do
    config = adapter_config.certification

    with {:ok, site_port} <- state.callback.http_port(state.id, state.arg),
         {:ok, acme_server_port} when not is_nil(acme_server_port) <- acme_server_port(config) do
      dns = dns(config, site_port)
      Acme.Server.start_link(config.id, acme_server_port, dns, log_level: config.log_level)
    else
      _ -> :ignore
    end
  end

  defp acme_server_port(%{directory_url: {:internal, acme_server_opts}}),
    do: Keyword.fetch(acme_server_opts, :port)

  defp acme_server_port(_), do: :error

  defp dns(config, endpoint_port),
    do: Enum.into(config.domains, %{}, &{&1, fn -> "localhost:#{endpoint_port}" end})
end
