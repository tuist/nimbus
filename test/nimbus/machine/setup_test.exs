defmodule Nimbus.Machine.SetupTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Machine.Setup
  alias Nimbus.Machine.Setup.Curie
  alias Nimbus.Machine.Setup.Geranos
  alias Nimbus.Machine.Setup.GitHubRunner

  setup :set_mimic_global
  setup :verify_on_exit!

  setup _context do
    Mimic.copy(Connection)
    Mimic.copy(GitHubRunner)
    Mimic.copy(Curie)
    Mimic.copy(Geranos)

    :ok
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    machine_env = %{"XDG_DATA_HOME" => tmp_dir}

    macos_machine = %Machine{
      id: "test-macos-machine",
      tenant_id: "test-tenant",
      provider_id: "test-provider",
      os: :macos,
      arch: :arm64,
      state: :provisioning,
      provider_metadata: %{type: :local, env: machine_env}
    }

    linux_machine = %Machine{
      id: "test-linux-machine",
      tenant_id: "test-tenant",
      provider_id: "test-provider",
      os: :linux,
      arch: :x86_64,
      state: :provisioning,
      provider_metadata: %{type: :local, env: machine_env}
    }

    data_home = Path.join(tmp_dir, "data")
    cache_home = Path.join(tmp_dir, "cache")
    state_home = Path.join(tmp_dir, "state")

    %{
      machine_env: machine_env,
      macos_machine: macos_machine,
      linux_machine: linux_machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    }
  end

  describe "setup/1 - integration" do
    @tag timeout: 600_000
    test "sets up a complete macOS machine", %{tmp_dir: tmp_dir} do
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

        result = Setup.setup(machine)

        case result do
          {:ok, updated_machine} ->
            assert updated_machine.state == :ready

            # Verify GitHub runner was installed
            # The XDG_DATA_HOME is tmp_dir, so paths are directly under it
            github_runner_path = Path.join([tmp_dir, "nimbus", "github-runner", "run.sh"])
            assert File.exists?(github_runner_path), "expected GitHub runner to be installed"

            # Verify Curie was installed
            curie_path = Path.join([tmp_dir, "nimbus", "curie", "bin", "curie"])
            assert File.exists?(curie_path), "expected Curie to be installed"

            # Verify Geranos was installed
            geranos_path = Path.join([tmp_dir, "nimbus", "geranos", "bin", "geranos"])
            assert File.exists?(geranos_path), "expected Geranos to be installed"

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

    @tag timeout: 600_000
    test "sets up a complete Linux machine", %{tmp_dir: tmp_dir} do
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

        result = Setup.setup(machine)

        case result do
          {:ok, updated_machine} ->
            assert updated_machine.state == :ready

            # Verify GitHub runner was installed
            # The XDG_DATA_HOME is tmp_dir, so paths are directly under it
            github_runner_path = Path.join([tmp_dir, "nimbus", "github-runner", "run.sh"])
            assert File.exists?(github_runner_path), "expected GitHub runner to be installed"

            # Curie and Geranos should not be installed on Linux
            curie_path = Path.join([tmp_dir, "nimbus", "curie", "bin", "curie"])
            refute File.exists?(curie_path), "Curie should not be installed on Linux"

            geranos_path = Path.join([tmp_dir, "nimbus", "geranos", "bin", "geranos"])
            refute File.exists?(geranos_path), "Geranos should not be installed on Linux"

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

  describe "setup/1" do
    test "sets up a macOS machine with all installers", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      # Mock directory operations
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      # Mock installers
      GitHubRunner
      |> expect(:install, fn ^machine -> {:ok, "/path/to/github-runner"} end)

      Curie
      |> expect(:install, fn ^machine -> {:ok, "/path/to/curie"} end)

      Geranos
      |> expect(:install, fn ^machine -> {:ok, "/path/to/geranos"} end)

      assert {:ok, updated_machine} = Setup.setup(machine)
      assert updated_machine.state == :ready
      assert updated_machine.id == machine.id
      assert updated_machine.os == :macos
    end

    test "sets up a Linux machine without macOS-specific tools", %{
      linux_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      # Mock directory operations
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      # Only GitHub runner should be installed for Linux
      GitHubRunner
      |> expect(:install, fn ^machine -> {:ok, "/path/to/github-runner"} end)

      # Curie and Geranos should NOT be called for Linux
      Curie
      |> stub(:install, fn ^machine ->
        flunk("Curie should not be called for Linux machines")
      end)

      Geranos
      |> stub(:install, fn ^machine ->
        flunk("Geranos should not be called for Linux machines")
      end)

      assert {:ok, updated_machine} = Setup.setup(machine)
      assert updated_machine.state == :ready
      assert updated_machine.id == machine.id
      assert updated_machine.os == :linux
    end

    test "returns error if XDG data home retrieval fails", %{macos_machine: machine} do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:error, :enoent} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory setup fails")
      end)

      assert {:error, :enoent} = Setup.setup(machine)
    end

    test "returns error if XDG cache home retrieval fails", %{
      macos_machine: machine,
      data_home: data_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:error, :enoent} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory setup fails")
      end)

      assert {:error, :enoent} = Setup.setup(machine)
    end

    test "returns error if XDG state home retrieval fails", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:error, :enoent} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory setup fails")
      end)

      assert {:error, :enoent} = Setup.setup(machine)
    end

    test "returns error if data directory creation fails", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> {:error, :eacces} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory creation fails")
      end)

      assert {:error, :eacces} = Setup.setup(machine)
    end

    test "returns error if cache directory creation fails", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> {:error, :eacces} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory creation fails")
      end)

      assert {:error, :eacces} = Setup.setup(machine)
    end

    test "returns error if state directory creation fails", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> {:error, :eacces} end)

      GitHubRunner
      |> stub(:install, fn ^machine ->
        flunk("installer should not be called when directory creation fails")
      end)

      assert {:error, :eacces} = Setup.setup(machine)
    end

    test "returns error if GitHub runner installation fails", %{
      linux_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      GitHubRunner
      |> expect(:install, fn ^machine -> {:error, :download_failed} end)

      Curie
      |> stub(:install, fn ^machine ->
        flunk("Curie should not be called when GitHub runner fails")
      end)

      assert {:error, :download_failed} = Setup.setup(machine)
    end

    test "returns error if Curie installation fails on macOS", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      GitHubRunner
      |> expect(:install, fn ^machine -> {:ok, "/path/to/github-runner"} end)

      Curie
      |> expect(:install, fn ^machine -> {:error, :verification_failed} end)

      Geranos
      |> stub(:install, fn ^machine ->
        flunk("Geranos should not be called when Curie fails")
      end)

      assert {:error, :verification_failed} = Setup.setup(machine)
    end

    test "returns error if Geranos installation fails on macOS", %{
      macos_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      GitHubRunner
      |> expect(:install, fn ^machine -> {:ok, "/path/to/github-runner"} end)

      Curie
      |> expect(:install, fn ^machine -> {:ok, "/path/to/curie"} end)

      Geranos
      |> expect(:install, fn ^machine -> {:error, :verification_failed} end)

      assert {:error, :verification_failed} = Setup.setup(machine)
    end

    test "preserves machine metadata on success", %{
      linux_machine: machine,
      data_home: data_home,
      cache_home: cache_home,
      state_home: state_home
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine -> {:ok, data_home} end)
      |> expect(:xdg_cache_home, fn ^machine -> {:ok, cache_home} end)
      |> expect(:xdg_state_home, fn ^machine -> {:ok, state_home} end)
      |> expect(:mkdir_p, fn ^machine, ^data_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^cache_home -> :ok end)
      |> expect(:mkdir_p, fn ^machine, ^state_home -> :ok end)

      GitHubRunner
      |> expect(:install, fn ^machine -> {:ok, "/path/to/github-runner"} end)

      assert {:ok, updated_machine} = Setup.setup(machine)
      assert updated_machine.id == machine.id
      assert updated_machine.tenant_id == machine.tenant_id
      assert updated_machine.provider_id == machine.provider_id
      assert updated_machine.os == machine.os
      assert updated_machine.arch == machine.arch
      assert updated_machine.provider_metadata == machine.provider_metadata
      assert updated_machine.state == :ready
    end
  end
end
