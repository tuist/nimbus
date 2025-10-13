defmodule Nimbus.Provider.Config do
  @moduledoc """
  Configuration for a provider.

  Each tenant can have multiple provider configurations, allowing them to use
  different cloud providers, multiple accounts with the same provider, or local
  machines for development and testing.
  """

  @type provider_type :: :aws | :hetzner | :gcp | :azure | :local

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          type: provider_type(),
          credentials: map(),
          config: map()
        }

  @enforce_keys [:id, :tenant_id, :type, :credentials]
  defstruct [:id, :tenant_id, :type, :credentials, config: %{}]

  @doc """
  Creates a new Provider.Config struct.

  ## Examples

      iex> Nimbus.Provider.Config.new(
      ...>   "provider-456",
      ...>   "tenant-123",
      ...>   :aws,
      ...>   %{access_key_id: "AKIA...", secret_access_key: "..."},
      ...>   %{region: "us-east-1", tags: %{"managed_by" => "nimbus"}}
      ...> )
      %Nimbus.Provider.Config{
        id: "provider-456",
        tenant_id: "tenant-123",
        type: :aws,
        credentials: %{access_key_id: "AKIA...", secret_access_key: "..."},
        config: %{region: "us-east-1", tags: %{"managed_by" => "nimbus"}}
      }
  """
  @spec new(String.t(), String.t(), provider_type(), map(), map()) :: t()
  def new(id, tenant_id, type, credentials, config \\ %{}) do
    %__MODULE__{
      id: id,
      tenant_id: tenant_id,
      type: type,
      credentials: credentials,
      config: config
    }
  end
end
