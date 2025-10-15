defmodule Nimbus.Machine.Setup.Geranos do
  @moduledoc """
  Geranos image puller installer (macOS only).

  Geranos is a macOS VM image puller from macvmio that handles downloading and
  managing macOS VM images. See https://github.com/macvmio/geranos for more information.

  This installer downloads and installs Geranos to XDG-compliant directories
  under `~/.local/share/nimbus/geranos`.

  ## Installation Process

  1. Determine the latest Geranos version from GitHub releases
  2. Download the appropriate binary for macOS architecture
  3. Install to `~/.local/share/nimbus/geranos/bin`
  4. Make binary executable
  5. Verify installation

  ## Platform Support

  Only macOS (arm64, x86_64) is supported. Linux machines will skip this installer.

  ## Examples

      machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      {:ok, install_path} = Nimbus.Machine.Setup.Geranos.install(machine)
      # => {:ok, "/Users/username/.local/share/nimbus/geranos"}
  """

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Provider.Local
  alias Nimbus.Telemetry

  require Telemetry

  # Pin to a specific version for determinism
  # Update this when upgrading Geranos
  @geranos_version "0.7.5"
  @geranos_tag "v#{@geranos_version}"
  @geranos_releases_url "https://api.github.com/repos/macvmio/geranos/releases/tags/#{@geranos_tag}"
  @install_subpath "geranos"

  @doc """
  Installs Geranos image puller for the given macOS machine.

  Downloads the latest version of Geranos and installs it to the XDG data
  directory under `geranos/bin/`.

  Returns `{:ok, install_path}` on success.
  Returns `{:error, :not_macos}` if called on non-macOS machine.
  Returns `{:error, reason}` on installation failure.

  ## Examples

      iex> machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      iex> Nimbus.Machine.Setup.Geranos.install(machine)
      {:ok, "/Users/username/.local/share/nimbus/geranos"}

      iex> machine = %Nimbus.Machine{os: :linux, ...}
      iex> Nimbus.Machine.Setup.Geranos.install(machine)
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

    Telemetry.span([:nimbus, :machine, :setup, :geranos], metadata, fn ->
      with {:ok, install_path} <- Connection.xdg_data_home(machine, @install_subpath),
           bin_path = Path.join(install_path, "bin"),
           :ok <- Connection.mkdir_p(machine, bin_path),
           {:ok, download_url} <- get_download_url(machine),
           {:ok, binary_path} <- download_geranos(machine, download_url, bin_path),
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
    case Req.get(@geranos_releases_url, headers: [{"accept", "application/vnd.github.v3+json"}]) do
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

    case Enum.find(assets, fn asset ->
           name = Map.get(asset, "name", "")

           mac_asset_name?(name) && Enum.any?(arch_tokens, &String.contains?(name, &1))
         end) do
      nil -> {:error, {:no_asset_found, List.first(arch_tokens)}}
      asset -> {:ok, Map.get(asset, "browser_download_url")}
    end
  end

  defp download_geranos(%Machine{} = machine, download_url, bin_path) do
    binary_name = "geranos"
    binary_path = Path.join(bin_path, binary_name)

    # Check if already installed
    case Connection.file_exists?(machine, binary_path) do
      {:ok, true} ->
        {:ok, binary_path}

      {:ok, false} ->
        cond do
          String.ends_with?(download_url, ".tar.gz") ->
            archive_path = Path.join(bin_path, "geranos.tar.gz")

            result =
              with {:ok, _} <-
                     exec_command(
                       machine,
                       "curl -L -o #{archive_path} #{download_url}",
                       timeout: 300_000
                     ),
                   {:ok, _} <-
                     exec_command(
                       machine,
                       "tar -xzf #{archive_path} -C #{bin_path} geranos"
                     ) do
                {:ok, binary_path}
              end

            _ = exec_command(machine, "rm -f #{archive_path}")
            result

          true ->
            with {:ok, _} <-
                   exec_command(
                     machine,
                     "curl -L -o #{binary_path} #{download_url}",
                     timeout: 300_000
                   ) do
              {:ok, binary_path}
            end
        end

      error ->
        error
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

  defp mac_asset_name?(name) do
    Enum.any?(["geranos-darwin-", "geranos_Darwin_"], &String.starts_with?(name, &1))
  end

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
