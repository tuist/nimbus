defmodule Nimbus.Machine.Setup.Curie do
  @moduledoc """
  Curie VM manager installer (macOS only).

  Curie is a macOS virtualization manager from macvmio that provides VM management
  capabilities. See https://github.com/macvmio/curie for more information.

  This installer downloads and installs Curie to XDG-compliant directories
  under `~/.local/share/nimbus/curie`.

  ## Installation Process

  1. Determine the latest Curie version from GitHub releases
  2. Download the appropriate binary for macOS architecture
  3. Install to `~/.local/share/nimbus/curie/bin`
  4. Make binary executable
  5. Verify installation

  ## Platform Support

  Only macOS (arm64, x86_64) is supported. Linux machines will skip this installer.

  ## Examples

      machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      {:ok, install_path} = Nimbus.Machine.Setup.Curie.install(machine)
      # => {:ok, "/Users/username/.local/share/nimbus/curie"}
  """

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Provider.Local
  alias Nimbus.Telemetry

  require Telemetry

  # Pin to a specific version for determinism
  # Update this when upgrading Curie
  # Note: Curie uses versions without 'v' prefix (e.g., "0.4.0" not "v0.4.0")
  @curie_version "0.4.0"
  @curie_releases_url "https://api.github.com/repos/macvmio/curie/releases/tags/#{@curie_version}"
  @install_subpath "curie"

  @doc """
  Installs Curie VM manager for the given macOS machine.

  Downloads the latest version of Curie and installs it to the XDG data
  directory under `curie/bin/`.

  Returns `{:ok, install_path}` on success.
  Returns `{:error, :not_macos}` if called on non-macOS machine.
  Returns `{:error, reason}` on installation failure.

  ## Examples

      iex> machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      iex> Nimbus.Machine.Setup.Curie.install(machine)
      {:ok, "/Users/username/.local/share/nimbus/curie"}

      iex> machine = %Nimbus.Machine{os: :linux, ...}
      iex> Nimbus.Machine.Setup.Curie.install(machine)
      {:error, :not_macos}
  """
  @spec install(Machine.t()) :: {:ok, String.t()} | {:error, term()}
  def install(%Machine{os: os}) when os != :macos do
    {:error, :not_macos}
  end

  def install(%Machine{os: :macos} = machine) do
    metadata = %{
      machine_id: machine.id,
      os: machine.os,
      arch: machine.arch
    }

    Telemetry.span([:nimbus, :machine, :setup, :curie], metadata, fn ->
      with {:ok, install_path} <- Connection.xdg_data_home(machine, @install_subpath),
           bin_path = Path.join(install_path, "bin"),
           :ok <- Connection.mkdir_p(machine, bin_path),
           {:ok, {download_url, filename}} <- get_download_url(machine),
           {:ok, binary_path} <-
             install_curie(machine, download_url, filename, install_path, bin_path),
           :ok <- make_executable(machine, binary_path),
           :ok <- verify_installation(machine, binary_path) do
        {{:ok, install_path}, Map.put(metadata, :install_path, install_path)}
      else
        {:error, reason} = error ->
          {error, Map.put(metadata, :error, reason)}
      end
    end)
  end

  # Private functions

  defp get_download_url(%Machine{arch: arch}) do
    case fetch_release_info() do
      {:ok, release_info} ->
        find_asset_url(release_info, arch)

      error ->
        error
    end
  end

  defp fetch_release_info do
    case Req.get(@curie_releases_url, headers: [{"accept", "application/vnd.github.v3+json"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp find_asset_url(release_info, arch) do
    assets = Map.get(release_info, "assets", [])
    arch_tokens = arch_tokens(arch)

    # Try to find architecture-specific binary first: curie-darwin-arm64, curie-darwin-amd64
    binary_asset =
      Enum.find(assets, fn asset ->
        name = Map.get(asset, "name", "")

        String.starts_with?(name, "curie-darwin-") &&
          Enum.any?(arch_tokens, &String.contains?(name, &1))
      end)

    # Fall back to .pkg installer if no binary found
    pkg_asset =
      Enum.find(assets, fn asset ->
        name = Map.get(asset, "name", "")
        String.ends_with?(name, ".pkg")
      end)

    case binary_asset || pkg_asset do
      nil -> {:error, {:no_asset_found, List.first(arch_tokens)}}
      asset -> {:ok, {Map.get(asset, "browser_download_url"), Map.get(asset, "name")}}
    end
  end

  defp install_curie(%Machine{} = machine, download_url, filename, _install_path, bin_path) do
    binary_name = "curie"
    binary_path = Path.join(bin_path, binary_name)

    # Check if already installed
    case Connection.file_exists?(machine, binary_path) do
      {:ok, true} ->
        {:ok, binary_path}

      {:ok, false} ->
        if String.ends_with?(filename, ".pkg") do
          install_from_pkg(machine, download_url, filename, bin_path, binary_path)
        else
          install_from_binary(machine, download_url, binary_path)
        end

      error ->
        error
    end
  end

  defp install_from_binary(%Machine{} = machine, download_url, binary_path) do
    with {:ok, _} <-
           exec_command(
             machine,
             "curl -L -o #{binary_path} #{download_url}",
             timeout: 300_000
           ) do
      {:ok, binary_path}
    end
  end

  defp install_from_pkg(%Machine{} = machine, download_url, filename, bin_path, binary_path) do
    # Download .pkg to temporary location
    with {:ok, cache_dir} <- Connection.xdg_cache_home(machine, "downloads"),
         :ok <- Connection.mkdir_p(machine, cache_dir) do
      pkg_path = Path.join(cache_dir, filename)

      result =
        with {:ok, _} <-
               exec_command(
                 machine,
                 "curl -L -o #{pkg_path} #{download_url}",
                 timeout: 300_000
               ),
             :ok <- extract_pkg(machine, pkg_path, bin_path, binary_path) do
          {:ok, binary_path}
        end

      # Clean up .pkg file
      _ = exec_command(machine, "rm -f #{pkg_path}")
      result
    end
  end

  defp extract_pkg(%Machine{} = machine, pkg_path, bin_path, binary_path) do
    # Create a temporary directory for extraction in parent of bin_path
    install_path = Path.dirname(bin_path)
    tmp_extract = Path.join(install_path, "tmp_extract")

    extract_commands = """
    mkdir -p #{tmp_extract} && \
    cd #{tmp_extract} && \
    xar -xf #{pkg_path} && \
    cat Payload | gunzip -dc | cpio -i && \
    find . -name curie -type f -exec cp {} #{binary_path} \\; && \
    cd - && \
    rm -rf #{tmp_extract}
    """

    case exec_command(machine, extract_commands, timeout: 300_000) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp make_executable(%Machine{} = machine, binary_path) do
    case exec_command(machine, "chmod +x #{binary_path}") do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp verify_installation(%Machine{} = machine, binary_path) do
    case exec_command(machine, "#{binary_path} --help") do
      {:ok, _output} ->
        :ok

      {:error, _} ->
        {:error, :verification_failed}
    end
  end

  defp arch_tokens(:arm64), do: ["arm64"]
  defp arch_tokens(:x86_64), do: ["x86_64", "amd64"]

  # Execute command based on machine provider type
  defp exec_command(machine, command, opts \\ [])

  defp exec_command(%Machine{provider_metadata: %{type: :local}} = machine, command, opts) do
    Local.exec_command(machine, command, opts)
  end

  # For future SSH-based execution
  defp exec_command(%Machine{} = _machine, _command, _opts) do
    {:error, :ssh_not_implemented}
  end
end
