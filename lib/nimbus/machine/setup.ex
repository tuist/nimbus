defmodule Nimbus.Machine.Setup do
  @moduledoc """
  Machine setup and provisioning logic.

  This module handles the installation of dependencies and configuration of
  machines after they've been provisioned by a cloud provider. It installs:

  - GitHub Actions runner (all platforms)
  - Curie VM manager (macOS only) - https://github.com/macvmio/curie
  - Geranos image puller (macOS only) - https://github.com/macvmio/geranos

  All installations follow XDG Base Directory conventions, with files placed
  under `~/.local/share/nimbus`.

  ## Setup Flow

  1. Create required directories (XDG-compliant)
  2. Install GitHub Actions runner
  3. Install macOS-specific tools (Curie, Geranos) if applicable
  4. Update machine state to :ready

  ## Examples

      # Setup a local macOS machine
      machine = %Nimbus.Machine{os: :macos, ...}
      {:ok, updated_machine} = Nimbus.Machine.Setup.setup(machine)

      # Setup a Linux machine (GitHub runner only)
      machine = %Nimbus.Machine{os: :linux, ...}
      {:ok, updated_machine} = Nimbus.Machine.Setup.setup(machine)
  """

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Machine.Setup.Curie
  alias Nimbus.Machine.Setup.Geranos
  alias Nimbus.Machine.Setup.GitHubRunner
  alias Nimbus.Telemetry

  require Telemetry

  @doc """
  Sets up a provisioned machine with required dependencies.

  This function:
  1. Creates XDG-compliant directories
  2. Installs GitHub Actions runner
  3. Installs Curie and Geranos (macOS only)
  4. Updates machine state to :ready

  Returns `{:ok, machine}` with updated state on success.
  Returns `{:error, reason}` if setup fails.

  ## Examples

      iex> machine = %Nimbus.Machine{id: "m1", os: :macos, state: :provisioning, ...}
      iex> Nimbus.Machine.Setup.setup(machine)
      {:ok, %Nimbus.Machine{state: :ready, ...}}
  """
  @spec setup(Machine.t()) :: {:ok, Machine.t()} | {:error, term()}
  def setup(%Machine{} = machine) do
    metadata = %{
      machine_id: machine.id,
      tenant_id: machine.tenant_id,
      os: machine.os
    }

    Telemetry.span([:nimbus, :machine, :setup], metadata, fn ->
      with :ok <- ensure_directories(machine),
           {:ok, _} <- GitHubRunner.install(machine),
           :ok <- install_macos_tools(machine) do
        updated_machine = %{machine | state: :ready}
        {{:ok, updated_machine}, metadata}
      else
        {:error, reason} = error ->
          {error, Map.put(metadata, :error, reason)}
      end
    end)
  end

  @doc """
  Returns information about installed tools and their versions.

  This function checks for installed tools and returns their versions,
  along with available Geranos images if applicable.

  Returns a map with:
  - `:github_runner` - Version info or `:not_installed`
  - `:curie` - Version info or `:not_installed` or `:not_available` (Linux)
  - `:geranos` - Map with version and images, or `:not_installed` or `:not_available` (Linux)

  ## Examples

      iex> machine = %Nimbus.Machine{os: :macos, ...}
      iex> Nimbus.Machine.Setup.info(machine)
      {:ok, %{
        github_runner: %{version: "2.321.0", path: "/path/to/runner"},
        curie: %{version: "0.4.0", path: "/path/to/curie"},
        geranos: %{version: "0.7.5", path: "/path/to/geranos", images: [...]}
      }}
  """
  @spec info(Machine.t()) :: {:ok, map()} | {:error, term()}
  def info(%Machine{} = machine) do
    with {:ok, github_runner_info} <- GitHubRunner.info(machine),
         {:ok, curie_info} <- Curie.info(machine),
         {:ok, geranos_info} <- Geranos.info(machine) do
      {:ok,
       %{
         github_runner: github_runner_info,
         curie: curie_info,
         geranos: geranos_info
       }}
    end
  end

  # Private functions

  defp ensure_directories(machine) do
    with {:ok, data_home} <- Connection.xdg_data_home(machine),
         {:ok, cache_home} <- Connection.xdg_cache_home(machine),
         {:ok, state_home} <- Connection.xdg_state_home(machine),
         :ok <- Connection.mkdir_p(machine, data_home),
         :ok <- Connection.mkdir_p(machine, cache_home) do
      Connection.mkdir_p(machine, state_home)
    end
  end

  defp install_macos_tools(%Machine{os: :macos} = machine) do
    with {:ok, _} <- Curie.install(machine),
         {:ok, _} <- Geranos.install(machine) do
      :ok
    end
  end

  defp install_macos_tools(%Machine{}), do: :ok
end
