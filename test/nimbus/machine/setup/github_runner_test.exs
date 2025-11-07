defmodule Nimbus.Machine.Setup.GitHubRunnerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Machine.Setup.GitHubRunner
  alias Nimbus.Provider.Local

  setup :set_mimic_global
  setup :verify_on_exit!

  setup _context do
    Mimic.copy(Connection)
    Mimic.copy(Local)
    Mimic.copy(Req)

    :ok
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    machine_env = %{"XDG_DATA_HOME" => tmp_dir}

    machine = %Machine{
      id: "test-machine",
      tenant_id: "test-tenant",
      provider_id: "test-provider",
      os: :macos,
      arch: :arm64,
      state: :provisioning,
      provider_metadata: %{type: :local, env: machine_env}
    }

    install_path = Path.join([tmp_dir, "github-runner"])
    cache_dir = Path.join([tmp_dir, "cache"])
    run_script = Path.join(install_path, "run.sh")
    tarball_path = Path.join(cache_dir, "actions-runner-osx-arm64-2.321.0.tar.gz")
    release_url = "https://api.github.com/repos/actions/runner/releases/tags/v2.321.0"

    %{
      machine_env: machine_env,
      machine: machine,
      install_path: install_path,
      cache_dir: cache_dir,
      run_script: run_script,
      tarball_path: tarball_path,
      release_url: release_url
    }
  end

  describe "install/1 - with real network" do
    @tag timeout: 300_000
    test "downloads and installs GitHub runner on macOS", %{tmp_dir: tmp_dir} do
      if :os.type() == {:unix, :darwin} do
        machine_env = %{
          "XDG_DATA_HOME" => tmp_dir,
          "XDG_CACHE_HOME" => tmp_dir,
          "HOME" => tmp_dir
        }

        arch =
          case :erlang.system_info(:system_architecture) |> to_string() do
            "aarch64" <> _ -> :arm64
            "arm64" <> _ -> :arm64
            "x86_64" <> _ -> :x86_64
            _ -> :arm64
          end

        machine = %Machine{
          id: "integration-machine",
          tenant_id: "test-tenant",
          provider_id: "test-provider",
          os: :macos,
          arch: arch,
          state: :provisioning,
          provider_metadata: %{type: :local, env: machine_env}
        }

        result = GitHubRunner.install(machine)

        case result do
          {:ok, install_path} ->
            run_script = Path.join(install_path, "run.sh")

            assert File.exists?(run_script), "expected run.sh to be installed"

            assert File.exists?(Path.join(install_path, "config.sh")),
                   "expected config.sh to be installed"

          {:error, {:http_error, 403}} ->
            # GitHub API rate limiting - skip test instead of failing
            :ok

          {:error, reason} ->
            flunk("unexpected integration failure: #{inspect(reason)}")
        end
      else
        :ok
      end
    end

    @tag timeout: 300_000
    test "downloads and installs GitHub runner on Linux", %{tmp_dir: tmp_dir} do
      if :os.type() == {:unix, :linux} do
        machine_env = %{
          "XDG_DATA_HOME" => tmp_dir,
          "XDG_CACHE_HOME" => tmp_dir,
          "HOME" => tmp_dir
        }

        arch =
          case :erlang.system_info(:system_architecture) |> to_string() do
            "aarch64" <> _ -> :arm64
            "arm64" <> _ -> :arm64
            "x86_64" <> _ -> :x86_64
            _ -> :x86_64
          end

        machine = %Machine{
          id: "integration-machine",
          tenant_id: "test-tenant",
          provider_id: "test-provider",
          os: :linux,
          arch: arch,
          state: :provisioning,
          provider_metadata: %{type: :local, env: machine_env}
        }

        result = GitHubRunner.install(machine)

        case result do
          {:ok, install_path} ->
            run_script = Path.join(install_path, "run.sh")

            assert File.exists?(run_script), "expected run.sh to be installed"

            assert File.exists?(Path.join(install_path, "config.sh")),
                   "expected config.sh to be installed"

          {:error, {:http_error, 403}} ->
            # GitHub API rate limiting - skip test instead of failing
            :ok

          {:error, reason} ->
            flunk("unexpected integration failure: #{inspect(reason)}")
        end
      else
        :ok
      end
    end
  end

  describe "install/1" do
    test "installs GitHub runner successfully for macOS machines", %{
      machine: machine,
      install_path: install_path,
      cache_dir: cache_dir,
      run_script: run_script,
      tarball_path: tarball_path,
      release_url: release_url
    } do
      download_url =
        "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, false} end)
      |> expect(:xdg_cache_home, fn ^machine, "downloads" -> {:ok, cache_dir} end)
      |> expect(:mkdir_p, fn ^machine, ^cache_dir -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, true} end)

      Req
      |> expect(:get, fn url, opts ->
        assert url == release_url
        assert Keyword.get(opts, :headers) == [{"accept", "application/vnd.github.v3+json"}]

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "actions-runner-osx-arm64-2.321.0.tar.gz",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          command == "curl -L -o #{tarball_path} #{download_url}" -> {:ok, ""}
          command == "tar -xzf #{tarball_path} -C #{install_path}" -> {:ok, ""}
          command == "rm -f #{tarball_path}" -> {:ok, ""}
          true -> flunk("unexpected command: #{command}")
        end
      end)

      assert {:ok, ^install_path} = GitHubRunner.install(machine)
    end

    test "installs GitHub runner successfully for Linux machines", %{
      machine_env: machine_env,
      install_path: install_path,
      cache_dir: cache_dir,
      release_url: release_url
    } do
      machine = %Machine{
        id: "linux-machine",
        tenant_id: "test-tenant",
        provider_id: "test-provider",
        os: :linux,
        arch: :x86_64,
        state: :provisioning,
        provider_metadata: %{type: :local, env: machine_env}
      }

      run_script = Path.join(install_path, "run.sh")
      tarball_path = Path.join(cache_dir, "actions-runner-linux-x64-2.321.0.tar.gz")

      download_url =
        "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, false} end)
      |> expect(:xdg_cache_home, fn ^machine, "downloads" -> {:ok, cache_dir} end)
      |> expect(:mkdir_p, fn ^machine, ^cache_dir -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, true} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "actions-runner-linux-x64-2.321.0.tar.gz",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          command == "curl -L -o #{tarball_path} #{download_url}" -> {:ok, ""}
          command == "tar -xzf #{tarball_path} -C #{install_path}" -> {:ok, ""}
          command == "rm -f #{tarball_path}" -> {:ok, ""}
          true -> flunk("unexpected command: #{command}")
        end
      end)

      assert {:ok, ^install_path} = GitHubRunner.install(machine)
    end

    test "handles GitHub API failures", %{
      machine: machine,
      install_path: install_path,
      release_url: release_url
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      Local
      |> stub(:exec_command, fn _machine, command, _opts ->
        flunk("unexpected command: #{command}")
      end)

      assert {:error, {:request_failed, %Req.TransportError{reason: :timeout}}} =
               GitHubRunner.install(machine)
    end

    test "handles missing release asset for platform", %{
      machine: machine,
      install_path: install_path,
      release_url: release_url
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url
        {:ok, %Req.Response{status: 200, body: %{"assets" => []}}}
      end)

      Local
      |> stub(:exec_command, fn _machine, command, _opts ->
        flunk("unexpected command: #{command}")
      end)

      assert {:error, {:no_asset_found, "osx-arm64"}} = GitHubRunner.install(machine)
    end

    test "propagates download failures", %{
      machine: machine,
      install_path: install_path,
      cache_dir: cache_dir,
      run_script: run_script,
      tarball_path: tarball_path,
      release_url: release_url
    } do
      download_url =
        "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, false} end)
      |> expect(:xdg_cache_home, fn ^machine, "downloads" -> {:ok, cache_dir} end)
      |> expect(:mkdir_p, fn ^machine, ^cache_dir -> :ok end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "actions-runner-osx-arm64-2.321.0.tar.gz",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        if command == "curl -L -o #{tarball_path} #{download_url}" do
          {:error, 1}
        else
          flunk("unexpected command: #{command}")
        end
      end)

      assert {:error, 1} = GitHubRunner.install(machine)
    end

    test "skips download when runner already installed", %{
      machine: machine,
      install_path: install_path,
      run_script: run_script,
      release_url: release_url
    } do
      download_url =
        "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, true} end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, true} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "actions-runner-osx-arm64-2.321.0.tar.gz",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        if String.contains?(command, "curl -L -o") do
          flunk("download should not run when runner already installed")
        else
          flunk("unexpected command: #{command}")
        end
      end)

      assert {:ok, ^install_path} = GitHubRunner.install(machine)
    end

    test "returns verification failure when run.sh not found", %{
      machine: machine,
      install_path: install_path,
      cache_dir: cache_dir,
      run_script: run_script,
      tarball_path: tarball_path,
      release_url: release_url
    } do
      download_url =
        "https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "github-runner" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^install_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, false} end)
      |> expect(:xdg_cache_home, fn ^machine, "downloads" -> {:ok, cache_dir} end)
      |> expect(:mkdir_p, fn ^machine, ^cache_dir -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^run_script -> {:ok, false} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "actions-runner-osx-arm64-2.321.0.tar.gz",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          command == "curl -L -o #{tarball_path} #{download_url}" -> {:ok, ""}
          command == "tar -xzf #{tarball_path} -C #{install_path}" -> {:ok, ""}
          command == "rm -f #{tarball_path}" -> {:ok, ""}
          true -> flunk("unexpected command: #{command}")
        end
      end)

      assert {:error, :verification_failed} = GitHubRunner.install(machine)
    end
  end
end
