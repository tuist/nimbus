defmodule Nimbus.Machine.Connection do
  @moduledoc """
  Handles machine communication abstraction across different provider types.

  This module provides a unified interface for executing commands on machines,
  regardless of whether they're local, remote via SSH, or use other connection
  methods. The connection details are extracted from the machine's provider_metadata.

  ## Connection Types

  ### Local
  For local development/testing machines:
  ```elixir
  %Machine{
    provider_metadata: %{
      type: :local,
      # No additional connection info needed
    }
  }
  ```

  ### SSH
  For remote machines accessed via SSH:
  ```elixir
  %Machine{
    ip_address: "54.123.45.67",
    ssh_public_key: "ssh-rsa AAAA...",
    provider_metadata: %{
      type: :aws,  # or :hetzner, :gcp, etc.
      ssh: %{
        user: "ubuntu",  # or "ec2-user" for Amazon Linux, "admin" for macOS
        port: 22,
        private_key_path: "/path/to/key.pem",  # Provided by integrator
        # Alternative: private_key: "-----BEGIN RSA PRIVATE KEY-----..."
      }
    }
  }
  ```

  ### Future: Docker Exec
  For containerized environments:
  ```elixir
  %Machine{
    provider_metadata: %{
      type: :docker,
      container_id: "abc123",
      docker_host: "unix:///var/run/docker.sock"
    }
  }
  ```

  ## Usage

      machine = %Nimbus.Machine{...}

      # Execute command
      {:ok, output} = Nimbus.Machine.Connection.exec(machine, "whoami")

      # Check if file exists
      {:ok, true} = Nimbus.Machine.Connection.file_exists?(machine, "/path/to/file")

      # Create directory
      :ok = Nimbus.Machine.Connection.mkdir_p(machine, "/path/to/dir")

  ## Path Resolution

  For SSH connections, all paths are resolved on the remote machine.
  XDG paths are constructed as shell commands:

      # Instead of calling XDG.data_home() locally:
      exec(machine, "echo ~/.local/share/nimbus")
  """

  alias Nimbus.Machine
  alias Nimbus.Provider.Local

  @type exec_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Executes a command on the machine.

  Returns `{:ok, output}` if successful, `{:error, reason}` otherwise.

  ## Examples

      iex> Nimbus.Machine.Connection.exec(machine, "echo 'hello'")
      {:ok, "hello\\n"}
  """
  @spec exec(Machine.t(), String.t(), keyword()) :: exec_result()
  def exec(%Machine{} = machine, command, opts \\ []) do
    case connection_type(machine) do
      :local -> exec_local(machine, command, opts)
      :ssh -> exec_ssh(machine, command, opts)
      other -> {:error, {:unsupported_connection_type, other}}
    end
  end

  @doc """
  Checks if a file exists on the machine.

  ## Examples

      iex> Nimbus.Machine.Connection.file_exists?(machine, "/etc/passwd")
      {:ok, true}
  """
  @spec file_exists?(Machine.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def file_exists?(%Machine{} = machine, path) do
    case exec(machine, "test -f #{shell_escape(path)} && echo 'yes' || echo 'no'") do
      {:ok, output} -> {:ok, String.trim(output) == "yes"}
      error -> error
    end
  end

  @doc """
  Checks if a directory exists on the machine.

  ## Examples

      iex> Nimbus.Machine.Connection.dir_exists?(machine, "/home/ubuntu")
      {:ok, true}
  """
  @spec dir_exists?(Machine.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def dir_exists?(%Machine{} = machine, path) do
    case exec(machine, "test -d #{shell_escape(path)} && echo 'yes' || echo 'no'") do
      {:ok, output} -> {:ok, String.trim(output) == "yes"}
      error -> error
    end
  end

  @doc """
  Creates a directory (and parents) on the machine.

  ## Examples

      iex> Nimbus.Machine.Connection.mkdir_p(machine, "/path/to/deep/dir")
      :ok
  """
  @spec mkdir_p(Machine.t(), String.t()) :: :ok | {:error, term()}
  def mkdir_p(%Machine{} = machine, path) do
    case exec(machine, "mkdir -p #{shell_escape(path)}") do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Resolves the XDG data home path on the remote machine.

  This returns the path as a string, but does NOT create it.
  Use `mkdir_p/2` to create it.

  ## Examples

      iex> Nimbus.Machine.Connection.xdg_data_home(machine, "github-runner")
      {:ok, "/home/ubuntu/.local/share/nimbus/github-runner"}
  """
  @spec xdg_data_home(Machine.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def xdg_data_home(%Machine{} = machine, subpath \\ nil) do
    base_cmd = ~s(echo "${XDG_DATA_HOME:-$HOME/.local/share}/nimbus")

    case exec(machine, base_cmd) do
      {:ok, base} ->
        path = String.trim(base)
        path = if subpath, do: Path.join(path, subpath), else: path
        {:ok, path}

      error ->
        error
    end
  end

  @doc """
  Resolves the XDG cache home path on the remote machine.

  ## Examples

      iex> Nimbus.Machine.Connection.xdg_cache_home(machine, "downloads")
      {:ok, "/home/ubuntu/.cache/nimbus/downloads"}
  """
  @spec xdg_cache_home(Machine.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def xdg_cache_home(%Machine{} = machine, subpath \\ nil) do
    base_cmd = ~s(echo "${XDG_CACHE_HOME:-$HOME/.cache}/nimbus")

    case exec(machine, base_cmd) do
      {:ok, base} ->
        path = String.trim(base)
        path = if subpath, do: Path.join(path, subpath), else: path
        {:ok, path}

      error ->
        error
    end
  end

  @doc """
  Resolves the XDG state home path on the remote machine.

  ## Examples

      iex> Nimbus.Machine.Connection.xdg_state_home(machine, "logs")
      {:ok, "/home/ubuntu/.local/state/nimbus/logs"}
  """
  @spec xdg_state_home(Machine.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def xdg_state_home(%Machine{} = machine, subpath \\ nil) do
    base_cmd = ~s(echo "${XDG_STATE_HOME:-$HOME/.local/state}/nimbus")

    case exec(machine, base_cmd) do
      {:ok, base} ->
        path = String.trim(base)
        path = if subpath, do: Path.join(path, subpath), else: path
        {:ok, path}

      error ->
        error
    end
  end

  # Private functions

  defp connection_type(%Machine{provider_metadata: %{type: :local}}), do: :local

  defp connection_type(%Machine{provider_metadata: metadata}) do
    # If SSH config is present, use SSH
    # Otherwise infer from provider type
    cond do
      Map.has_key?(metadata, :ssh) -> :ssh
      metadata[:type] in [:aws, :hetzner, :gcp, :azure] -> :ssh
      true -> :unknown
    end
  end

  defp exec_local(machine, command, opts) do
    Local.exec_command(machine, command, opts)
  end

  defp exec_ssh(%Machine{} = machine, command, opts) do
    # TODO: Implement SSH execution
    # This will use the SSH module when it's implemented
    # For now, return not implemented
    _ = {machine, command, opts}
    {:error, :ssh_not_implemented}
  end

  # Escape shell arguments to prevent injection
  defp shell_escape(arg) do
    # Simple escaping - wrap in single quotes and escape any single quotes
    escaped = String.replace(arg, "'", "'\\''")
    "'#{escaped}'"
  end
end
