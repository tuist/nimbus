defmodule Nimbus.Telemetry do
  @moduledoc """
  Telemetry integration for Nimbus.

  Nimbus emits telemetry events for all significant operations, allowing integrating
  applications to monitor, log, and track the lifecycle of machines, forge operations,
  provider API calls, and SSH commands.

  ## Event Naming Convention

  All events follow the pattern: `[:nimbus, :category, :event_name]`

  Categories:
  - `:machine` - Machine lifecycle events (provision, setup, terminate)
  - `:forge` - Git forge operations (register/unregister runners)
  - `:provider` - Cloud provider API calls
  - `:ssh` - SSH operations (connect, execute commands)

  ## Event Types

  Most operations emit three events:
  - `:start` - Operation begins (includes monotonic start time)
  - `:success` - Operation completes successfully (includes duration)
  - `:failure` - Operation fails (includes duration and error)

  ## Subscribing to Events

  To handle telemetry events in your application:

      :telemetry.attach_many(
        "my-app-nimbus-handler",
        [
          [:nimbus, :machine, :provision_start],
          [:nimbus, :machine, :provision_success],
          [:nimbus, :machine, :provision_failure]
        ],
        &MyApp.TelemetryHandler.handle_event/4,
        nil
      )

      defmodule MyApp.TelemetryHandler do
        require Logger

        def handle_event([:nimbus, :machine, :provision_success], measurements, metadata, _config) do
          Logger.info("Machine provisioned",
            tenant_id: metadata.tenant_id,
            machine_id: metadata.machine_id,
            duration_ms: measurements.duration
          )
        end

        # ... other handlers
      end

  ## Common Metadata

  All events include:
  - `:tenant_id` - Tenant identifier
  - `:machine_id` - Machine identifier (when applicable)
  - `:provider_type` - Provider type (`:aws`, `:local`, etc.) (when applicable)

  Additional metadata varies by event type - see individual event documentation.
  """

  @doc """
  Emits a machine lifecycle start event.

  ## Examples

      iex> Nimbus.Telemetry.machine_start(:provision, %{tenant_id: "tenant-123", machine_id: "machine-456"})
      :ok
  """
  @spec machine_start(atom(), map()) :: :ok
  def machine_start(operation, metadata) when is_atom(operation) and is_map(metadata) do
    :telemetry.execute(
      [:nimbus, :machine, :"#{operation}_start"],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a machine lifecycle success event.

  ## Examples

      iex> Nimbus.Telemetry.machine_success(:provision, start_time, %{tenant_id: "tenant-123", machine_id: "machine-456"})
      :ok
  """
  @spec machine_success(atom(), integer(), map()) :: :ok
  def machine_success(operation, start_time, metadata)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :machine, :"#{operation}_success"],
      %{duration: duration},
      metadata
    )
  end

  @doc """
  Emits a machine lifecycle failure event.

  ## Examples

      iex> Nimbus.Telemetry.machine_failure(:provision, start_time, %{tenant_id: "tenant-123"}, :timeout)
      :ok
  """
  @spec machine_failure(atom(), integer(), map(), term()) :: :ok
  def machine_failure(operation, start_time, metadata, error)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :machine, :"#{operation}_failure"],
      %{duration: duration},
      Map.put(metadata, :error, error)
    )
  end

  @doc """
  Emits a machine ready event (special event without start/success/failure pattern).

  ## Examples

      iex> Nimbus.Telemetry.machine_ready(%{tenant_id: "tenant-123", machine_id: "machine-456"})
      :ok
  """
  @spec machine_ready(map()) :: :ok
  def machine_ready(metadata) when is_map(metadata) do
    :telemetry.execute(
      [:nimbus, :machine, :ready],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a forge operation start event.

  ## Examples

      iex> Nimbus.Telemetry.forge_start(:register_runner, %{tenant_id: "tenant-123", forge_type: :github})
      :ok
  """
  @spec forge_start(atom(), map()) :: :ok
  def forge_start(operation, metadata) when is_atom(operation) and is_map(metadata) do
    :telemetry.execute(
      [:nimbus, :forge, :"#{operation}_start"],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a forge operation success event.

  ## Examples

      iex> Nimbus.Telemetry.forge_success(:register_runner, start_time, %{tenant_id: "tenant-123", runner_id: "runner-789"})
      :ok
  """
  @spec forge_success(atom(), integer(), map()) :: :ok
  def forge_success(operation, start_time, metadata)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :forge, :"#{operation}_success"],
      %{duration: duration},
      metadata
    )
  end

  @doc """
  Emits a forge operation failure event.

  ## Examples

      iex> Nimbus.Telemetry.forge_failure(:register_runner, start_time, %{tenant_id: "tenant-123"}, :api_error)
      :ok
  """
  @spec forge_failure(atom(), integer(), map(), term()) :: :ok
  def forge_failure(operation, start_time, metadata, error)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :forge, :"#{operation}_failure"],
      %{duration: duration},
      Map.put(metadata, :error, error)
    )
  end

  @doc """
  Emits a provider API call start event.

  ## Examples

      iex> Nimbus.Telemetry.provider_start(:api_call, %{tenant_id: "tenant-123", provider_type: :aws, operation: "RunInstances"})
      :ok
  """
  @spec provider_start(atom(), map()) :: :ok
  def provider_start(operation, metadata) when is_atom(operation) and is_map(metadata) do
    :telemetry.execute(
      [:nimbus, :provider, :"#{operation}_start"],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a provider API call success event.

  ## Examples

      iex> Nimbus.Telemetry.provider_success(:api_call, start_time, %{tenant_id: "tenant-123", provider_type: :aws})
      :ok
  """
  @spec provider_success(atom(), integer(), map()) :: :ok
  def provider_success(operation, start_time, metadata)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :provider, :"#{operation}_success"],
      %{duration: duration},
      metadata
    )
  end

  @doc """
  Emits a provider API call failure event.

  ## Examples

      iex> Nimbus.Telemetry.provider_failure(:api_call, start_time, %{tenant_id: "tenant-123"}, :throttled)
      :ok
  """
  @spec provider_failure(atom(), integer(), map(), term()) :: :ok
  def provider_failure(operation, start_time, metadata, error)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :provider, :"#{operation}_failure"],
      %{duration: duration},
      Map.put(metadata, :error, error)
    )
  end

  @doc """
  Emits an SSH operation start event.

  ## Examples

      iex> Nimbus.Telemetry.ssh_start(:connect, %{machine_id: "machine-456", host: "1.2.3.4"})
      :ok
  """
  @spec ssh_start(atom(), map()) :: :ok
  def ssh_start(operation, metadata) when is_atom(operation) and is_map(metadata) do
    :telemetry.execute(
      [:nimbus, :ssh, :"#{operation}_start"],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits an SSH operation success event.

  ## Examples

      iex> Nimbus.Telemetry.ssh_success(:connect, start_time, %{machine_id: "machine-456"})
      :ok
  """
  @spec ssh_success(atom(), integer(), map()) :: :ok
  def ssh_success(operation, start_time, metadata)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :ssh, :"#{operation}_success"],
      %{duration: duration},
      metadata
    )
  end

  @doc """
  Emits an SSH operation failure event.

  ## Examples

      iex> Nimbus.Telemetry.ssh_failure(:connect, start_time, %{machine_id: "machine-456"}, :timeout)
      :ok
  """
  @spec ssh_failure(atom(), integer(), map(), term()) :: :ok
  def ssh_failure(operation, start_time, metadata, error)
      when is_atom(operation) and is_integer(start_time) and is_map(metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:nimbus, :ssh, :"#{operation}_failure"],
      %{duration: duration},
      Map.put(metadata, :error, error)
    )
  end

  @doc """
  Convenience macro for wrapping operations with start/success/failure telemetry.

  ## Examples

      use Nimbus.Telemetry

      def provision_machine(config, specs) do
        metadata = %{tenant_id: config.tenant_id, provider_type: config.type}

        telemetry :machine, :provision, metadata do
          # Your provisioning logic here
          Provider.provision(config, specs)
        end
      end
  """
  defmacro telemetry(category, operation, metadata, do: block) do
    quote do
      start_time = System.monotonic_time()
      metadata = unquote(metadata)

      case unquote(category) do
        :machine -> Nimbus.Telemetry.machine_start(unquote(operation), metadata)
        :forge -> Nimbus.Telemetry.forge_start(unquote(operation), metadata)
        :provider -> Nimbus.Telemetry.provider_start(unquote(operation), metadata)
        :ssh -> Nimbus.Telemetry.ssh_start(unquote(operation), metadata)
      end

      try do
        result = unquote(block)

        case unquote(category) do
          :machine -> Nimbus.Telemetry.machine_success(unquote(operation), start_time, metadata)
          :forge -> Nimbus.Telemetry.forge_success(unquote(operation), start_time, metadata)
          :provider -> Nimbus.Telemetry.provider_success(unquote(operation), start_time, metadata)
          :ssh -> Nimbus.Telemetry.ssh_success(unquote(operation), start_time, metadata)
        end

        result
      rescue
        error ->
          case unquote(category) do
            :machine ->
              Nimbus.Telemetry.machine_failure(unquote(operation), start_time, metadata, error)

            :forge ->
              Nimbus.Telemetry.forge_failure(unquote(operation), start_time, metadata, error)

            :provider ->
              Nimbus.Telemetry.provider_failure(unquote(operation), start_time, metadata, error)

            :ssh ->
              Nimbus.Telemetry.ssh_failure(unquote(operation), start_time, metadata, error)
          end

          reraise error, __STACKTRACE__
      end
    end
  end

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Nimbus.Telemetry, only: [telemetry: 4]
    end
  end
end
