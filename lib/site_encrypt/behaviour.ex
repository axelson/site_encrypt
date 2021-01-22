# NOTE: I *think* this module should be able to replace the usage of the
# endpoint as an ID, which would be another nice simplification.
defmodule SiteEncrypt.Behaviour do
  @doc """
  Invoked during startup to obtain certification info.

  See `configure/1` for details.
  """
  @callback certification() :: SiteEncrypt.certification()

  @doc "Invoked after the new certificate has been obtained."
  @callback handle_new_cert() :: any

  @optional_callbacks handle_new_cert: 0
end
