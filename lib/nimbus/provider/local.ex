defmodule Nimbus.Provider.Local do
  @moduledoc """
  Local provider implementation for development and testing.

  The local provider allows you to use your development machine as a runner
  without provisioning cloud infrastructure. This is useful for:
  - Local development and testing
  - CI/CD pipeline testing without cloud costs
  - Integration testing of the Nimbus system

  Unlike cloud providers, the local provider:
  - Does not provision new machines (uses localhost)
  - Executes commands directly via MuonTrap instead of SSH
  - Has no minimum allocation periods or termination restrictions
  - Requires no credentials (runs on the current machine)

  ## Configuration

      config = Nimbus.Provider.Config.new(
        "local-provider",
        "tenant-123",
        :local,
        %{},  # No credentials needed
        %{name: "dev-machine"}  # Optional config
      )

  ## Security Note

  Local providers should only be used in development/testing environments.
  Do not use local providers in production as they bypass the security isolation
  that cloud providers offer.
  """

  @behaviour Nimbus.Provider

  alias Nimbus.Machine
  alias Nimbus.Machine.Setup
  alias Nimbus.Provider.Config

  @impl true
  def provision(%Config{type: :local} = config, specs) do
    machine_id = generate_machine_id()
    name = get_in(config.config, [:name]) || "localhost"
    skip_setup = Map.get(specs, :skip_setup, false)

    machine =
      Machine.new(
        machine_id,
        config.tenant_id,
        config.id,
        detect_os(specs),
        detect_arch(specs),
        :provisioning,
        ip_address: "127.0.0.1",
        ssh_public_key: nil,
        labels: Map.get(specs, :labels, []),
        created_at: DateTime.utc_now(),
        provider_metadata: %{
          type: :local,
          name: name,
          hostname: get_hostname()
        }
      )

    # Run setup unless explicitly skipped (useful for testing)
    if skip_setup do
      {:ok, %{machine | state: :ready}}
    else
      Setup.setup(machine)
    end
  end

  @impl true
  def terminate(%Config{type: :local}, %Machine{}) do
    # No-op for local machines - they're not actually provisioned
    :ok
  end

  @impl true
  def can_terminate?(%Machine{provider_metadata: %{type: :local}}) do
    # Local machines can always be "terminated" (which is a no-op)
    {:ok, true}
  end

  @impl true
  def list_machines(%Config{type: :local}, _tenant_id) do
    # For local provider, we can't really "list" machines since they're not tracked
    # externally. This would need to be handled by the integrating application's
    # storage if they want to track local machines.
    # For now, return empty list
    {:ok, []}
  end

  @impl true
  def get_machine(%Config{type: :local}, _machine_id) do
    # Similar to list_machines, we can't query local machines from an external API
    # The integrating application would need to track these if needed
    {:error, :not_found}
  end

  # Private functions

  defp generate_machine_id do
    "local-#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp detect_os(specs) do
    # Prefer explicit OS from specs
    case Map.get(specs, :os) do
      os when os in [:macos, :linux] ->
        os

      nil ->
        # Auto-detect from system
        case :os.type() do
          {:unix, :darwin} -> :macos
          {:unix, _} -> :linux
          _ -> :linux
        end
    end
  end

  defp detect_arch(specs) do
    # Prefer explicit arch from specs
    case Map.get(specs, :arch) do
      arch when arch in [:arm64, :x86_64] ->
        arch

      nil ->
        # Auto-detect from system
        case :erlang.system_info(:system_architecture) |> to_string() do
          "aarch64" <> _ -> :arm64
          "arm64" <> _ -> :arm64
          "x86_64" <> _ -> :x86_64
          _ -> :x86_64
        end
    end
  end

  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      _ -> "unknown"
    end
  end

  @doc """
  Executes a command on a local machine.

  This is a helper function that can be used instead of SSH for local machines.
  It runs the command directly using MuonTrap, which provides better process
  management and cleanup than System.cmd.

  ## Examples

      iex> machine = %Machine{provider_metadata: %{type: :local}}
      iex> Nimbus.Provider.Local.exec_command(machine, "echo 'hello'")
      {:ok, "hello\\n"}

      iex> Nimbus.Provider.Local.exec_command(machine, "invalid_command")
      {:error, 127}
  """
  @spec exec_command(Machine.t(), String.t(), keyword()) ::
          {:ok, output :: String.t()} | {:error, exit_code :: integer()}
  def exec_command(machine, command, opts \\ [])

  def exec_command(%Machine{provider_metadata: %{type: :local} = metadata}, command, opts) do
    # Default timeout of 60 seconds if not specified
    timeout = Keyword.get(opts, :timeout, 60_000)

    env_from_metadata =
      metadata
      |> Map.get(:env, %{})
      |> normalize_env()

    env_from_opts =
      opts
      |> Keyword.get(:env, %{})
      |> normalize_env()

    env =
      env_from_metadata
      |> Map.merge(env_from_opts)
      |> Map.to_list()

    case MuonTrap.cmd("sh", ["-c", command],
           into: "",
           stderr_to_stdout: true,
           timeout: timeout,
           env: env
         ) do
      {output, 0} ->
        {:ok, output}

      {_output, exit_code} ->
        {:error, exit_code}
    end
  rescue
    error ->
      {:error, {:exception, error}}
  end

  def exec_command(%Machine{}, _command, _opts) do
    {:error, :not_local_machine}
  end

  defp normalize_env(env) when is_map(env) do
    env
    |> Map.new(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    env
    |> Map.new(fn
      {key, value} -> {to_string(key), to_string(value)}
      key when is_binary(key) -> {key, ""}
    end)
  end

  defp normalize_env(_), do: %{}
end
