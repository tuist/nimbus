defmodule Nimbus.Forge.Config do
  @moduledoc """
  Configuration for a Git forge (GitHub, GitLab, Forgejo, etc.).

  Each tenant has one forge configuration that determines where their
  CI runners will be registered.
  """

  @type forge_type :: :github | :gitlab | :forgejo

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          type: forge_type(),
          credentials: map(),
          org: String.t()
        }

  @enforce_keys [:tenant_id, :type, :credentials, :org]
  defstruct [:tenant_id, :type, :credentials, :org]

  @doc """
  Creates a new Forge.Config struct.

  ## Examples

      # GitHub App configuration
      iex> Nimbus.Forge.Config.new(
      ...>   "tenant-123",
      ...>   :github,
      ...>   %{
      ...>     app_id: "123456",
      ...>     installation_id: "789012",
      ...>     private_key: "-----BEGIN RSA PRIVATE KEY-----..."
      ...>   },
      ...>   "tuist"
      ...> )
      %Nimbus.Forge.Config{
        tenant_id: "tenant-123",
        type: :github,
        credentials: %{
          app_id: "123456",
          installation_id: "789012",
          private_key: "-----BEGIN RSA PRIVATE KEY-----..."
        },
        org: "tuist"
      }

      # GitLab token configuration
      iex> Nimbus.Forge.Config.new(
      ...>   "tenant-456",
      ...>   :gitlab,
      ...>   %{token: "glpat-..."},
      ...>   "my-group"
      ...> )
      %Nimbus.Forge.Config{
        tenant_id: "tenant-456",
        type: :gitlab,
        credentials: %{token: "glpat-..."},
        org: "my-group"
      }
  """
  @spec new(String.t(), forge_type(), map(), String.t()) :: t()
  def new(tenant_id, type, credentials, org) do
    %__MODULE__{
      tenant_id: tenant_id,
      type: type,
      credentials: credentials,
      org: org
    }
  end
end
