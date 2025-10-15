defmodule Nimbus.Machine.Setup.CurieTest do
  use ExUnit.Case, async: false
  use Mimic

  import Bitwise

  alias Nimbus.Machine
  alias Nimbus.Machine.Connection
  alias Nimbus.Machine.Setup.Curie
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

    install_path = Path.join([tmp_dir, "curie"])
    bin_path = Path.join(install_path, "bin")
    binary_path = Path.join(bin_path, "curie")
    cache_dir = Path.join([tmp_dir, "cache"])
    pkg_path = Path.join(cache_dir, "curie-0.4.0.pkg")
    release_url = "https://api.github.com/repos/macvmio/curie/releases/tags/0.4.0"

    %{
      machine_env: machine_env,
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      binary_path: binary_path,
      cache_dir: cache_dir,
      pkg_path: pkg_path,
      release_url: release_url
    }
  end

  describe "install/1 - integration" do
    @tag :integration
    @tag timeout: 120_000
    test "downloads and installs curie on macOS", %{tmp_dir: tmp_dir} do
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

        result = Curie.install(machine)

        case result do
          {:ok, install_path} ->
            bin_path = Path.join(install_path, "bin")
            binary_path = Path.join(bin_path, "curie")

            assert File.exists?(binary_path), "expected curie binary to be installed"

            stat = File.stat!(binary_path)
            assert (stat.mode &&& 0o111) != 0, "binary should be executable"

          {:error, reason} ->
            flunk("unexpected integration failure: #{inspect(reason)}")
        end
      else
        :ok
      end
    end
  end

  describe "install/1" do
    test "returns error for non-macOS machines", %{machine_env: machine_env} do
      machine = %Machine{
        id: "linux-machine",
        tenant_id: "test-tenant",
        provider_id: "test-provider",
        os: :linux,
        arch: :x86_64,
        state: :provisioning,
        provider_metadata: %{type: :local, env: machine_env}
      }

      assert {:error, :not_macos} = Curie.install(machine)
    end

    test "installs curie successfully for macOS machines", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      binary_path: binary_path,
      release_url: release_url
    } do
      download_url = "https://example.com/curie-darwin-arm64"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^binary_path -> {:ok, false} end)

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
                 "name" => "curie-darwin-arm64",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          command == "curl -L -o #{binary_path} #{download_url}" -> {:ok, ""}
          command == "chmod +x #{binary_path}" -> {:ok, ""}
          command == "#{binary_path} --help" -> {:ok, "usage"}
          true -> flunk("unexpected command: #{command}")
        end
      end)

      assert {:ok, ^install_path} = Curie.install(machine)
    end

    test "handles GitHub API failures", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      release_url: release_url
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)

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
               Curie.install(machine)
    end

    test "handles missing release asset for architecture", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      release_url: release_url
    } do
      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url
        {:ok, %Req.Response{status: 200, body: %{"assets" => []}}}
      end)

      Local
      |> stub(:exec_command, fn _machine, command, _opts ->
        flunk("unexpected command: #{command}")
      end)

      assert {:error, {:no_asset_found, "arm64"}} = Curie.install(machine)
    end

    test "propagates download failures", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      binary_path: binary_path,
      release_url: release_url
    } do
      download_url = "https://example.com/curie-darwin-arm64"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^binary_path -> {:ok, false} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "curie-darwin-arm64",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        if command == "curl -L -o #{binary_path} #{download_url}" do
          {:error, 1}
        else
          flunk("unexpected command: #{command}")
        end
      end)

      assert {:error, 1} = Curie.install(machine)
    end

    test "skips download when binary already exists", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      binary_path: binary_path,
      release_url: release_url
    } do
      download_url = "https://example.com/curie-darwin-arm64"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^binary_path -> {:ok, true} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "curie-darwin-arm64",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          String.contains?(command, "curl -L -o") ->
            flunk("download should not run when binary already exists")

          command == "chmod +x #{binary_path}" ->
            {:ok, ""}

          command == "#{binary_path} --help" ->
            {:ok, "usage"}

          true ->
            flunk("unexpected command: #{command}")
        end
      end)

      assert {:ok, ^install_path} = Curie.install(machine)
    end

    test "returns verification failure when binary check fails", %{
      machine: machine,
      install_path: install_path,
      bin_path: bin_path,
      binary_path: binary_path,
      release_url: release_url
    } do
      download_url = "https://example.com/curie-darwin-arm64"

      Connection
      |> expect(:xdg_data_home, fn ^machine, "curie" -> {:ok, install_path} end)
      |> expect(:mkdir_p, fn ^machine, ^bin_path -> :ok end)
      |> expect(:file_exists?, fn ^machine, ^binary_path -> {:ok, false} end)

      Req
      |> expect(:get, fn url, _opts ->
        assert url == release_url

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "assets" => [
               %{
                 "name" => "curie-darwin-arm64",
                 "browser_download_url" => download_url
               }
             ]
           }
         }}
      end)

      Local
      |> stub(:exec_command, fn ^machine, command, _opts ->
        cond do
          command == "curl -L -o #{binary_path} #{download_url}" -> {:ok, ""}
          command == "chmod +x #{binary_path}" -> {:ok, ""}
          command == "#{binary_path} --help" -> {:error, 1}
          true -> flunk("unexpected command: #{command}")
        end
      end)

      assert {:error, :verification_failed} = Curie.install(machine)
    end
  end
end
