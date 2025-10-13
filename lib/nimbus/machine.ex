defmodule Nimbus.Machine do
  @moduledoc """
  Represents a provisioned CI runner machine.

  A machine abstracts away provider-specific details and provides a unified
  interface for managing runners across different cloud providers. Most machine
  information is queried from the cloud provider rather than stored locally.

  ## Image Lifecycle

  Machines can have associated images (AMIs, Docker images) that determine their
  software configuration. The image state tracks readiness:

  - `:provisioning` - Image is being downloaded/installed
  - `:ready` - Image is installed and machine is ready to use
  - For Linux with pre-built images, state goes directly to `:ready`
  - For macOS, images require post-provision setup (Xcode installation, etc.)

  ## Future: Multiple VMs per Machine

  Currently, each Machine represents one runtime environment. In the future, this
  may be extended to support multiple VMs per physical host (e.g., 2 VMs per Mac).
  """

  @type os :: :macos | :linux
  @type arch :: :arm64 | :x86_64
  @type state :: :provisioning | :image_installing | :ready | :running | :stopping | :terminated
  @type image_type :: :ami | :docker | nil

  @type image :: %{
          id: String.t(),
          type: image_type(),
          state: :provisioning | :ready,
          installed_at: DateTime.t() | nil
        }

  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          provider_id: String.t(),
          os: os(),
          arch: arch(),
          state: state(),
          ip_address: String.t() | nil,
          ssh_public_key: String.t() | nil,
          labels: [String.t()],
          image: image() | nil,
          created_at: DateTime.t() | nil,
          provider_metadata: map()
        }

  @enforce_keys [:id, :tenant_id, :provider_id, :os, :arch, :state]
  defstruct [
    :id,
    :tenant_id,
    :provider_id,
    :os,
    :arch,
    :state,
    :ip_address,
    :ssh_public_key,
    :image,
    :created_at,
    labels: [],
    provider_metadata: %{}
  ]

  @doc """
  Creates a new Machine struct.

  ## Examples

      iex> Nimbus.Machine.new(
      ...>   "machine-uuid",
      ...>   "tenant-123",
      ...>   "provider-456",
      ...>   :macos,
      ...>   :arm64,
      ...>   :running,
      ...>   ip_address: "1.2.3.4",
      ...>   labels: ["macos", "xcode-15"],
      ...>   provider_metadata: %{
      ...>     instance_id: "i-123abc",
      ...>     host_id: "h-456def",
      ...>     minimum_allocation_hours: 24
      ...>   }
      ...> )
      %Nimbus.Machine{
        id: "machine-uuid",
        tenant_id: "tenant-123",
        provider_id: "provider-456",
        os: :macos,
        arch: :arm64,
        state: :running,
        ip_address: "1.2.3.4",
        labels: ["macos", "xcode-15"],
        provider_metadata: %{
          instance_id: "i-123abc",
          host_id: "h-456def",
          minimum_allocation_hours: 24
        }
      }
  """
  @spec new(String.t(), String.t(), String.t(), os(), arch(), state(), keyword()) :: t()
  def new(id, tenant_id, provider_id, os, arch, state, opts \\ []) do
    %__MODULE__{
      id: id,
      tenant_id: tenant_id,
      provider_id: provider_id,
      os: os,
      arch: arch,
      state: state,
      ip_address: Keyword.get(opts, :ip_address),
      ssh_public_key: Keyword.get(opts, :ssh_public_key),
      labels: Keyword.get(opts, :labels, []),
      created_at: Keyword.get(opts, :created_at),
      provider_metadata: Keyword.get(opts, :provider_metadata, %{})
    }
  end

  @doc """
  Returns true if the machine is in a terminal state (stopped or terminated).

  ## Examples

      iex> machine = %Nimbus.Machine{state: :terminated}
      iex> Nimbus.Machine.terminated?(machine)
      true

      iex> machine = %Nimbus.Machine{state: :running}
      iex> Nimbus.Machine.terminated?(machine)
      false
  """
  @spec terminated?(t()) :: boolean()
  def terminated?(%__MODULE__{state: state}) when state in [:terminated, :stopping], do: true
  def terminated?(%__MODULE__{}), do: false

  @doc """
  Returns true if the machine is running and accessible.

  ## Examples

      iex> machine = %Nimbus.Machine{state: :running}
      iex> Nimbus.Machine.running?(machine)
      true

      iex> machine = %Nimbus.Machine{state: :provisioning}
      iex> Nimbus.Machine.running?(machine)
      false
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{state: :running}), do: true
  def running?(%__MODULE__{}), do: false

  @doc """
  Returns true if the machine is ready to accept work (image installed, fully configured).

  A machine is ready when its image is installed and it's in the :ready or :running state.

  ## Examples

      iex> machine = %Nimbus.Machine{state: :ready, image: %{state: :ready}}
      iex> Nimbus.Machine.ready?(machine)
      true

      iex> machine = %Nimbus.Machine{state: :image_installing}
      iex> Nimbus.Machine.ready?(machine)
      false

      iex> machine = %Nimbus.Machine{state: :ready, image: nil}
      iex> Nimbus.Machine.ready?(machine)
      true
  """
  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{state: state}) when state in [:ready, :running], do: true
  def ready?(%__MODULE__{}), do: false
end
