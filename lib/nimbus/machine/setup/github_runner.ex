defmodule Nimbus.Machine.Setup.GitHubRunner do
  @moduledoc """
  GitHub Actions runner installer.

  Downloads and installs the GitHub Actions runner agent for the appropriate
  platform and architecture. The runner is installed to XDG-compliant directories
  under `~/.local/share/nimbus/github-runner`.

  ## Installation Process

  1. Determine the latest runner version from GitHub API
  2. Download the appropriate runner tarball for the OS/architecture
  3. Extract to `~/.local/share/nimbus/github-runner`
  4. Verify installation by checking for the `run.sh` script

  ## Supported Platforms

  - macOS (arm64, x86_64)
  - Linux (arm64, x86_64)

  ## Examples

      machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      {:ok, install_path} = Nimbus.Machine.Setup.GitHubRunner.install(machine)
      # => {:ok, "/Users/username/.local/share/nimbus/github-runner"}
  """

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Telemetry

  require Telemetry

  # Pin to a specific version for determinism
  # Update this when upgrading GitHub Actions runner
  @github_runner_version "2.321.0"
  @github_runner_releases_url "https://api.github.com/repos/actions/runner/releases/tags/v#{@github_runner_version}"
  @install_subpath "github-runner"

  @doc """
  Installs the GitHub Actions runner for the given machine.

  Downloads the latest version of the GitHub Actions runner and installs it
  to the XDG data directory under `github-runner/`.

  Returns `{:ok, install_path}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> machine = %Nimbus.Machine{os: :macos, arch: :arm64, ...}
      iex> Nimbus.Machine.Setup.GitHubRunner.install(machine)
      {:ok, "/Users/username/.local/share/nimbus/github-runner"}
  """
  @spec install(Machine.t()) :: {:ok, String.t()} | {:error, term()}
  def install(%Machine{} = machine) do
    metadata = %{
      machine_id: machine.id,
      os: machine.os,
      arch: machine.arch
    }

    Telemetry.span([:nimbus, :machine, :setup, :github_runner], metadata, fn ->
      with {:ok, install_path} <- Connection.xdg_data_home(machine, @install_subpath),
           :ok <- Connection.mkdir_p(machine, install_path),
           {:ok, download_url} <- get_download_url(machine),
           {:ok, result} <- download_runner(machine, download_url, install_path),
           :ok <- maybe_extract_runner(machine, result, install_path),
           :ok <- verify_installation(machine, install_path) do
        {{:ok, install_path}, Map.put(metadata, :install_path, install_path)}
      else
        {:error, reason} = error ->
          {error, Map.put(metadata, :error, reason)}
      end
    end)
  end

  @doc """
  Returns information about the GitHub Actions runner installation.

  Returns `{:ok, map}` with version and path if installed.
  Returns `{:ok, :not_installed}` if not found.

  ## Examples

      iex> machine = %Nimbus.Machine{os: :macos, ...}
      iex> Nimbus.Machine.Setup.GitHubRunner.info(machine)
      {:ok, %{version: "2.321.0", path: "/path/to/runner"}}
  """
  @spec info(Machine.t()) :: {:ok, map() | :not_installed} | {:error, term()}
  def info(%Machine{} = machine) do
    with {:ok, install_path} <- Connection.xdg_data_home(machine, @install_subpath),
         run_script = Path.join(install_path, "run.sh"),
         {:ok, true} <- Connection.file_exists?(machine, run_script) do
      case get_runner_version(machine, run_script) do
        {:ok, version} ->
          {:ok, %{version: version, path: install_path}}

        {:error, _} ->
          {:ok, %{version: :unknown, path: install_path}}
      end
    else
      {:ok, false} -> {:ok, :not_installed}
      {:error, _} -> {:ok, :not_installed}
    end
  end

  # Private functions

  defp get_download_url(%Machine{os: os, arch: arch}) do
    platform_string = platform_string(os, arch)

    case fetch_release_info() do
      {:ok, release_info} ->
        find_asset_url(release_info, platform_string)

      error ->
        error
    end
  end

  defp fetch_release_info do
    case Req.get(@github_runner_releases_url,
           headers: [{"accept", "application/vnd.github.v3+json"}]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp find_asset_url(release_info, platform_string) do
    assets = Map.get(release_info, "assets", [])

    case Enum.find(assets, fn asset ->
           name = Map.get(asset, "name", "")
           String.contains?(name, platform_string) && String.ends_with?(name, ".tar.gz")
         end) do
      nil -> {:error, {:no_asset_found, platform_string}}
      asset -> {:ok, Map.get(asset, "browser_download_url")}
    end
  end

  defp download_runner(%Machine{} = machine, download_url, install_path) do
    # Check if already installed - skip download if run.sh exists
    run_script = Path.join(install_path, "run.sh")

    case Connection.file_exists?(machine, run_script) do
      {:ok, true} ->
        {:ok, :already_installed}

      {:ok, false} ->
        with {:ok, cache_dir} <- Connection.xdg_cache_home(machine, "downloads"),
             :ok <- Connection.mkdir_p(machine, cache_dir) do
          filename = Path.basename(URI.parse(download_url).path)
          tarball_path = Path.join(cache_dir, filename)

          with {:ok, _} <-
                 exec_command(
                   machine,
                   "curl -L -o #{tarball_path} #{download_url}",
                   timeout: 300_000
                 ) do
            {:ok, tarball_path}
          end
        end

      error ->
        error
    end
  end

  defp maybe_extract_runner(_machine, :already_installed, _install_path) do
    :ok
  end

  defp maybe_extract_runner(%Machine{} = machine, tarball_path, install_path) when is_binary(tarball_path) do
    extract_command = "tar -xzf #{tarball_path} -C #{install_path}"

    result =
      case exec_command(machine, extract_command, timeout: 120_000) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end

    # Clean up tarball after extraction attempt
    _ = exec_command(machine, "rm -f #{tarball_path}")
    result
  end

  defp verify_installation(%Machine{} = machine, install_path) do
    run_script = Path.join(install_path, "run.sh")

    case Connection.file_exists?(machine, run_script) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error, :verification_failed}

      {:error, _} = error ->
        error
    end
  end

  defp platform_string(:macos, :arm64), do: "osx-arm64"
  defp platform_string(:macos, :x86_64), do: "osx-x64"
  defp platform_string(:linux, :arm64), do: "linux-arm64"
  defp platform_string(:linux, :x86_64), do: "linux-x64"

  defp get_runner_version(%Machine{} = machine, run_script) do
    case Connection.exec(machine, "#{run_script} --version", timeout: 10_000) do
      {:ok, output} ->
        # Extract version from output (first line)
        version =
          output
          |> String.split("\n", parts: 2)
          |> List.first()
          |> String.trim()

        {:ok, version}

      {:error, _} = error ->
        error
    end
  end

  # Execute command via Connection abstraction
  defp exec_command(%Machine{} = machine, command, opts \\ []) do
    Connection.exec(machine, command, opts)
  end
end
