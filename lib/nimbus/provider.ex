defmodule Nimbus.Provider do
  @moduledoc """
  Behavior for cloud provider implementations.

  This behavior defines the interface that all cloud provider implementations must follow.
  Each provider (AWS, Hetzner, GCP, Azure, etc.) implements this behavior to handle
  provider-specific provisioning, termination, and machine management logic.

  ## Implementation

  Provider implementations should be placed in modules like:
  - `Nimbus.Provider.AWS`
  - `Nimbus.Provider.Hetzner`
  - `Nimbus.Provider.GCP`
  - `Nimbus.Provider.Local`

  ## Example Implementation

      defmodule Nimbus.Provider.AWS do
        @behaviour Nimbus.Provider

        alias Nimbus.Machine
        alias Nimbus.Provider.Config

        @impl true
        def provision(%Config{} = config, specs) do
          # AWS-specific provisioning logic
          # - Allocate dedicated host (for Mac)
          # - Launch EC2 instance
          # - Tag with tenant_id
          # - Return Machine struct
          {:ok, %Machine{...}}
        end

        @impl true
        def terminate(%Config{} = config, %Machine{} = machine) do
          # Terminate instance and release host if needed
          :ok
        end

        # ... implement other callbacks
      end
  """

  alias Nimbus.Machine
  alias Nimbus.Provider.AWS
  alias Nimbus.Provider.Azure
  alias Nimbus.Provider.Config
  alias Nimbus.Provider.GCP
  alias Nimbus.Provider.Hetzner
  alias Nimbus.Provider.Local

  @doc """
  Provisions a new machine with the specified configuration.

  The `specs` map contains machine requirements:
  - `:os` - Operating system (`:macos`, `:linux`) (optional for local)
  - `:arch` - Architecture (`:arm64`, `:x86_64`) (optional for local)
  - `:labels` - Labels for the machine/runner (e.g., `["xcode-15", "macos"]`)
  - `:ssh_public_key` - SSH public key for access (optional for local)
  - `:image_id` - Image identifier (AMI ID, Docker image, etc.) (optional)
  - `:image_type` - Image type (`:ami`, `:docker`) (optional)
  - `:setup_script` - Post-provision setup script path/commands (optional)

  The provider should:
  1. Provision the necessary infrastructure (hosts, instances, etc.)
  2. Tag resources with `tenant_id` for discovery
  3. If `image_id` provided, set machine state to `:provisioning` and populate `image` field
  4. Return a Machine struct with provider-specific metadata

  ## Examples

      # Basic provision
      iex> config = %Config{type: :aws, tenant_id: "tenant-123", ...}
      iex> specs = %{os: :macos, arch: :arm64, labels: ["xcode-15"]}
      iex> Provider.provision(config, specs)
      {:ok, %Machine{
        id: "machine-uuid",
        tenant_id: "tenant-123",
        state: :provisioning,
        provider_metadata: %{instance_id: "i-123abc", host_id: "h-456def"}
      }}

      # With image
      iex> specs = %{os: :macos, arch: :arm64, image_id: "ami-123", image_type: :ami}
      iex> Provider.provision(config, specs)
      {:ok, %Machine{
        state: :provisioning,
        image: %{id: "ami-123", type: :ami, state: :provisioning, installed_at: nil}
      }}

      iex> Provider.provision(config, %{os: :invalid})
      {:error, :unsupported_os}
  """
  @callback provision(config :: Config.t(), specs :: map()) ::
              {:ok, Machine.t()} | {:error, term()}

  @doc """
  Terminates a machine and releases associated resources.

  The provider should:
  1. Terminate the instance
  2. Release any dedicated resources (e.g., AWS dedicated hosts)
  3. Clean up tags and metadata

  Note: This callback should only be called after checking `can_terminate?/1`
  to ensure minimum allocation periods are respected.

  ## Examples

      iex> config = %Config{type: :aws, ...}
      iex> machine = %Machine{id: "machine-123", ...}
      iex> Provider.terminate(config, machine)
      :ok

      iex> Provider.terminate(config, machine)
      {:error, :instance_not_found}
  """
  @callback terminate(config :: Config.t(), machine :: Machine.t()) ::
              :ok | {:error, term()}

  @doc """
  Checks if a machine can be terminated.

  Some providers have minimum allocation periods (e.g., AWS Mac has 24 hours).
  This callback checks if the machine has met its minimum allocation period.

  ## Examples

      iex> machine = %Machine{created_at: ~U[2025-01-15 10:00:00Z], ...}
      iex> Provider.can_terminate?(machine)
      {:ok, true}

      iex> machine = %Machine{created_at: ~U[2025-01-15 22:00:00Z], ...}
      iex> Provider.can_terminate?(machine)
      {:error, :minimum_allocation_period, hours_remaining: 12}
  """
  @callback can_terminate?(machine :: Machine.t()) ::
              {:ok, true} | {:error, :minimum_allocation_period, hours_remaining: integer()}

  @doc """
  Lists all machines for a tenant by querying the cloud provider.

  The provider should query its API and filter by the tenant's tags to find
  all machines belonging to the tenant. This implements the "lean state" principle
  where machine information is queried from the provider rather than stored locally.

  ## Examples

      iex> config = %Config{type: :aws, ...}
      iex> Provider.list_machines(config, "tenant-123")
      {:ok, [
        %Machine{id: "machine-1", tenant_id: "tenant-123", state: :running},
        %Machine{id: "machine-2", tenant_id: "tenant-123", state: :provisioning}
      ]}

      iex> Provider.list_machines(config, "tenant-no-machines")
      {:ok, []}
  """
  @callback list_machines(config :: Config.t(), tenant_id :: String.t()) ::
              {:ok, [Machine.t()]} | {:error, term()}

  @doc """
  Retrieves a specific machine by querying the cloud provider.

  ## Examples

      iex> config = %Config{type: :aws, ...}
      iex> Provider.get_machine(config, "machine-123")
      {:ok, %Machine{id: "machine-123", state: :running}}

      iex> Provider.get_machine(config, "nonexistent")
      {:error, :not_found}
  """
  @callback get_machine(config :: Config.t(), machine_id :: String.t()) ::
              {:ok, Machine.t()} | {:error, term()}

  @doc """
  Returns the provider implementation module for a given provider type.

  ## Examples

      iex> Nimbus.Provider.impl(:aws)
      Nimbus.Provider.AWS

      iex> Nimbus.Provider.impl(:local)
      Nimbus.Provider.Local

      iex> Nimbus.Provider.impl(:unsupported)
      ** (ArgumentError) Unsupported provider: :unsupported
  """
  @spec impl(Config.provider_type()) :: module()
  def impl(:aws), do: AWS

  def impl(:hetzner), do: Hetzner

  def impl(:gcp), do: GCP

  def impl(:azure), do: Azure

  def impl(:local), do: Local

  def impl(type) do
    raise ArgumentError, "Unsupported provider: #{inspect(type)}"
  end

  @doc """
  Delegates to the appropriate provider implementation's provision/2.
  """
  @spec provision(Config.t(), map()) :: {:ok, Machine.t()} | {:error, term()}
  def provision(%Config{type: type} = config, specs) do
    impl(type).provision(config, specs)
  end

  @doc """
  Delegates to the appropriate provider implementation's terminate/2.
  """
  @spec terminate(Config.t(), Machine.t()) :: :ok | {:error, term()}
  def terminate(%Config{type: type} = config, machine) do
    impl(type).terminate(config, machine)
  end

  @doc """
  Delegates to the appropriate provider implementation's can_terminate?/1.
  """
  @spec can_terminate?(Machine.t()) ::
          {:ok, true} | {:error, :minimum_allocation_period, hours_remaining: integer()}
  def can_terminate?(%Machine{provider_id: provider_id} = machine) do
    with {:ok, config} <- Nimbus.Storage.get_provider(provider_id) do
      impl(config.type).can_terminate?(machine)
    end
  end

  @doc """
  Delegates to the appropriate provider implementation's list_machines/2.
  """
  @spec list_machines(Config.t(), String.t()) :: {:ok, [Machine.t()]} | {:error, term()}
  def list_machines(%Config{type: type} = config, tenant_id) do
    impl(type).list_machines(config, tenant_id)
  end

  @doc """
  Delegates to the appropriate provider implementation's get_machine/2.
  """
  @spec get_machine(Config.t(), String.t()) :: {:ok, Machine.t()} | {:error, term()}
  def get_machine(%Config{type: type} = config, machine_id) do
    impl(type).get_machine(config, machine_id)
  end
end
