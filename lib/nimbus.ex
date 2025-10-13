defmodule Nimbus do
  @moduledoc """
  Nimbus - CI Runner Provisioning and Management

  Nimbus is an Elixir library for provisioning and managing CI runner environments.
  It integrates with cloud providers (AWS, Hetzner, Local, etc.) and Git forges
  (GitHub, GitLab, Forgejo) to create on-demand runner infrastructure.

  ## Overview

  Nimbus acts as a glue layer between:
  - **Storage Layer**: Provided by the integrating application (tenants, configs)
  - **Cloud Providers**: AWS, Hetzner, GCP, Azure, or local machines
  - **Git Forges**: GitHub, GitLab, Forgejo (runner registration)

  ## Configuration

  Configure the storage implementation in your application config:

      config :nimbus, :storage, MyApp.NimbusStorage

  The storage module must implement the `Nimbus.Storage` behavior.

  ## Basic Usage

      # Provision a new machine
      {:ok, machine} = Nimbus.provision_machine(
        "tenant-123",
        "provider-456",
        %{
          os: :macos,
          arch: :arm64,
          labels: ["xcode-15", "macos"]
        }
      )

      # List all machines for a tenant
      {:ok, machines} = Nimbus.list_machines("tenant-123")

      # Get a specific machine
      {:ok, machine} = Nimbus.get_machine("tenant-123", "machine-789")

      # Check if a machine can be terminated
      {:ok, true} = Nimbus.can_terminate_machine?("tenant-123", "machine-789")

      # Terminate a machine
      :ok = Nimbus.terminate_machine("tenant-123", "machine-789")

  ## Telemetry

  Nimbus emits telemetry events for all operations. Subscribe to events:

      :telemetry.attach_many(
        "my-app-nimbus",
        [
          [:nimbus, :machine, :provision_start],
          [:nimbus, :machine, :provision_success],
          [:nimbus, :machine, :provision_failure]
        ],
        &MyApp.TelemetryHandler.handle_event/4,
        nil
      )

  See `Nimbus.Telemetry` for all available events.

  ## Architecture

  - `Nimbus.Storage` - Behavior for storage operations (implemented by integrator)
  - `Nimbus.Provider` - Behavior for cloud provider implementations
  - `Nimbus.Machine` - Machine data structure and utilities
  - `Nimbus.Telemetry` - Telemetry event emission
  - `Nimbus.Forge` - Git forge integration (future)
  """

  use Nimbus.Telemetry

  alias Nimbus.Provider.Config, as: ProviderConfig
  alias Nimbus.{Machine, Provider, Storage}

  @doc """
  Provisions a new machine for a tenant using the specified provider.

  ## Parameters

  - `tenant_id` - The tenant identifier
  - `provider_id` - The provider configuration ID to use
  - `specs` - Machine specifications map with keys:
    - `:os` - Operating system (`:macos`, `:linux`) (optional, auto-detected for local)
    - `:arch` - Architecture (`:arm64`, `:x86_64`) (optional, auto-detected for local)
    - `:labels` - List of labels for the runner (e.g., `["xcode-15", "macos"]`)
    - `:ssh_public_key` - SSH public key for access (optional for local provider)
    - `:image_id` - Image identifier (AMI ID, Docker image, etc.) (optional)
    - `:image_type` - Image type (`:ami`, `:docker`) (optional)
    - `:setup_script` - Post-provision setup script path/commands (optional)

  ## Returns

  - `{:ok, machine}` - Successfully provisioned machine
  - `{:error, reason}` - Provisioning failed

  ## Examples

      # Provision a machine
      Nimbus.provision_machine("tenant-123", "provider-456", %{
        os: :macos,
        arch: :arm64,
        labels: ["xcode-15"]
      })
      # => {:ok, %Nimbus.Machine{id: "machine-789", state: :running, ...}}

      # Invalid tenant
      Nimbus.provision_machine("invalid", "provider-456", %{})
      # => {:error, :tenant_not_found}
  """
  @spec provision_machine(String.t(), String.t(), map()) ::
          {:ok, Machine.t()} | {:error, term()}
  def provision_machine(tenant_id, provider_id, specs) do
    with {:ok, _tenant} <- Storage.get_tenant(tenant_id),
         {:ok, provider_config} <- Storage.get_provider(provider_id),
         :ok <- validate_provider_tenant(provider_config, tenant_id) do
      metadata = %{
        tenant_id: tenant_id,
        provider_id: provider_id,
        provider_type: provider_config.type
      }

      start_time = System.monotonic_time()
      Nimbus.Telemetry.machine_start(:provision, metadata)

      case Provider.provision(provider_config, specs) do
        {:ok, machine} = result ->
          Nimbus.Telemetry.machine_success(
            :provision,
            start_time,
            Map.put(metadata, :machine_id, machine.id)
          )

          result

        {:error, reason} = error ->
          Nimbus.Telemetry.machine_failure(:provision, start_time, metadata, reason)
          error
      end
    end
  end

  @doc """
  Terminates a machine and releases associated resources.

  This function will:
  1. Verify the machine belongs to the tenant
  2. Check if the machine can be terminated (minimum allocation periods)
  3. Terminate the machine via the provider
  4. Emit telemetry events

  ## Parameters

  - `tenant_id` - The tenant identifier
  - `machine_id` - The machine identifier to terminate

  ## Returns

  - `:ok` - Machine terminated successfully
  - `{:error, reason}` - Termination failed

  ## Examples

      # Terminate a machine successfully
      Nimbus.terminate_machine("tenant-123", "machine-789")
      # => :ok

      # Cannot terminate before minimum allocation period
      Nimbus.terminate_machine("tenant-123", "machine-789")
      # => {:error, {:minimum_allocation_period, hours_remaining: 12}}

      # Machine not found
      Nimbus.terminate_machine("tenant-123", "invalid")
      # => {:error, :machine_not_found}
  """
  @spec terminate_machine(String.t(), String.t()) :: :ok | {:error, term()}
  def terminate_machine(tenant_id, machine_id) do
    with {:ok, _tenant} <- Storage.get_tenant(tenant_id),
         {:ok, provider_config} <- get_provider_for_machine(machine_id),
         {:ok, machine} <- Provider.get_machine(provider_config, machine_id),
         :ok <- validate_machine_tenant(machine, tenant_id),
         {:ok, true} <- Provider.can_terminate?(machine) do
      metadata = %{
        tenant_id: tenant_id,
        machine_id: machine_id,
        provider_type: provider_config.type
      }

      start_time = System.monotonic_time()
      Nimbus.Telemetry.machine_start(:terminate, metadata)

      case Provider.terminate(provider_config, machine) do
        :ok ->
          Nimbus.Telemetry.machine_success(:terminate, start_time, metadata)
          :ok

        {:error, reason} = error ->
          Nimbus.Telemetry.machine_failure(:terminate, start_time, metadata, reason)
          error
      end
    end
  end

  @doc """
  Lists all machines for a tenant.

  This queries all provider configurations for the tenant and aggregates
  machines from each provider.

  ## Parameters

  - `tenant_id` - The tenant identifier

  ## Returns

  - `{:ok, machines}` - List of machines (may be empty)
  - `{:error, reason}` - Failed to list machines

  ## Examples

      # List machines for a tenant
      Nimbus.list_machines("tenant-123")
      # => {:ok, [%Nimbus.Machine{id: "machine-1", ...}, %Nimbus.Machine{id: "machine-2", ...}]}

      # No machines for tenant
      Nimbus.list_machines("tenant-no-machines")
      # => {:ok, []}

      # Invalid tenant
      Nimbus.list_machines("invalid")
      # => {:error, :tenant_not_found}
  """
  @spec list_machines(String.t()) :: {:ok, [Machine.t()]} | {:error, term()}
  def list_machines(tenant_id) do
    with {:ok, _tenant} <- Storage.get_tenant(tenant_id),
         {:ok, provider_configs} <- Storage.list_tenant_providers(tenant_id) do
      machines =
        provider_configs
        |> Enum.flat_map(fn config ->
          case Provider.list_machines(config, tenant_id) do
            {:ok, machines} -> machines
            {:error, _} -> []
          end
        end)

      {:ok, machines}
    end
  end

  @doc """
  Retrieves a specific machine by ID.

  This function searches across all providers configured for the tenant
  to find the machine.

  ## Parameters

  - `tenant_id` - The tenant identifier
  - `machine_id` - The machine identifier

  ## Returns

  - `{:ok, machine}` - Machine found
  - `{:error, :not_found}` - Machine not found
  - `{:error, reason}` - Other errors

  ## Examples

      # Get a specific machine
      Nimbus.get_machine("tenant-123", "machine-789")
      # => {:ok, %Nimbus.Machine{id: "machine-789", state: :running, ...}}

      # Machine not found
      Nimbus.get_machine("tenant-123", "invalid")
      # => {:error, :not_found}
  """
  @spec get_machine(String.t(), String.t()) :: {:ok, Machine.t()} | {:error, term()}
  def get_machine(tenant_id, machine_id) do
    with {:ok, _tenant} <- Storage.get_tenant(tenant_id),
         {:ok, provider_config} <- get_provider_for_machine(machine_id),
         {:ok, machine} <- Provider.get_machine(provider_config, machine_id),
         :ok <- validate_machine_tenant(machine, tenant_id) do
      {:ok, machine}
    end
  end

  @doc """
  Checks if a machine can be terminated.

  Some providers have minimum allocation periods (e.g., AWS Mac instances
  have a 24-hour minimum). This function checks if those constraints are met.

  ## Parameters

  - `tenant_id` - The tenant identifier
  - `machine_id` - The machine identifier

  ## Returns

  - `{:ok, true}` - Machine can be terminated
  - `{:error, :minimum_allocation_period, hours_remaining: n}` - Must wait n hours
  - `{:error, reason}` - Other errors

  ## Examples

      # Machine can be terminated
      Nimbus.can_terminate_machine?("tenant-123", "machine-789")
      # => {:ok, true}

      # Cannot terminate yet (minimum allocation period)
      Nimbus.can_terminate_machine?("tenant-123", "machine-789")
      # => {:error, :minimum_allocation_period, hours_remaining: 12}
  """
  @spec can_terminate_machine?(String.t(), String.t()) ::
          {:ok, true}
          | {:error, :minimum_allocation_period, hours_remaining: integer()}
          | {:error, term()}
  def can_terminate_machine?(tenant_id, machine_id) do
    with {:ok, _tenant} <- Storage.get_tenant(tenant_id),
         {:ok, provider_config} <- get_provider_for_machine(machine_id),
         {:ok, machine} <- Provider.get_machine(provider_config, machine_id),
         :ok <- validate_machine_tenant(machine, tenant_id) do
      Provider.can_terminate?(machine)
    end
  end

  # Private functions

  defp validate_provider_tenant(%ProviderConfig{tenant_id: provider_tenant_id}, tenant_id)
       when provider_tenant_id != tenant_id do
    {:error, :provider_not_owned_by_tenant}
  end

  defp validate_provider_tenant(_provider_config, _tenant_id), do: :ok

  defp validate_machine_tenant(%Machine{tenant_id: machine_tenant_id}, tenant_id) when machine_tenant_id != tenant_id do
    {:error, :machine_not_owned_by_tenant}
  end

  defp validate_machine_tenant(_machine, _tenant_id), do: :ok

  defp get_provider_for_machine(_machine_id) do
    # Note: This is a simplification for now. In reality, we need to either:
    # 1. Encode provider_id in machine_id (e.g., "provider-123:machine-456")
    # 2. Have the integrator's storage track machine->provider mappings
    # 3. Search all providers (expensive)
    #
    # For the MVP with local provider, the Machine struct already has provider_id,
    # so we can use Storage.get_provider directly when we have the Machine object.
    #
    # This function is needed for operations that start with just machine_id.
    # TODO: Implement proper provider lookup strategy
    {:error, :provider_lookup_not_implemented}
  end
end
