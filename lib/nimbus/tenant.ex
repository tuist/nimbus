defmodule Nimbus.Tenant do
  @moduledoc """
  Represents a tenant in the Nimbus system.

  A tenant is an organization or entity that uses Nimbus to provision
  and manage CI runner environments. Each tenant has their own providers,
  forge configuration, and machines.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t()
        }

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @doc """
  Creates a new Tenant struct.

  ## Examples

      iex> Nimbus.Tenant.new("tenant-123", "Acme Corp")
      %Nimbus.Tenant{id: "tenant-123", name: "Acme Corp"}
  """
  @spec new(String.t(), String.t()) :: t()
  def new(id, name) do
    %__MODULE__{
      id: id,
      name: name
    }
  end
end
