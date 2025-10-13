defmodule Nimbus.Storage do
  @moduledoc """
  Behavior for storage operations that must be implemented by the integrating application.

  Nimbus is storage-agnostic and relies on the integrating application (e.g., Tuist server)
  to provide persistence for tenant, provider, and forge configuration data.

  ## Implementation

  The integrating application should implement this behavior and configure it in their
  application config:

      config :nimbus, :storage, MyApp.NimbusStorage

  ## Example Implementation

      defmodule MyApp.NimbusStorage do
        @behaviour Nimbus.Storage

        alias Nimbus.Forge.Config, as: ForgeConfig
        alias Nimbus.Provider.Config, as: ProviderConfig
        alias Nimbus.Tenant

        @impl true
        def get_tenant(tenant_id) do
          case MyApp.Repo.get(MyApp.Tenants.Tenant, tenant_id) do
            nil -> {:error, :not_found}
            tenant -> {:ok, Tenant.new(tenant.id, tenant.name)}
          end
        end

        @impl true
        def list_tenant_providers(tenant_id) do
          providers = MyApp.Repo.all(
            from p in MyApp.Providers.Provider,
            where: p.tenant_id == ^tenant_id
          )

          configs = Enum.map(providers, fn p ->
            ProviderConfig.new(p.id, p.tenant_id, p.type, p.credentials, p.config)
          end)

          {:ok, configs}
        end

        # ... implement other callbacks
      end
  """

  alias Nimbus.Forge.Config, as: ForgeConfig
  alias Nimbus.Provider.Config, as: ProviderConfig
  alias Nimbus.Tenant

  @doc """
  Retrieves a tenant by ID.

  ## Examples

      iex> Storage.get_tenant("tenant-123")
      {:ok, %Nimbus.Tenant{id: "tenant-123", name: "Acme Corp"}}

      iex> Storage.get_tenant("nonexistent")
      {:error, :not_found}
  """
  @callback get_tenant(tenant_id :: String.t()) ::
              {:ok, Tenant.t()} | {:error, :not_found}

  @doc """
  Lists all provider configurations for a tenant.

  ## Examples

      iex> Storage.list_tenant_providers("tenant-123")
      {:ok, [
        %Nimbus.Provider.Config{
          id: "provider-456",
          tenant_id: "tenant-123",
          type: :aws,
          ...
        }
      ]}

      iex> Storage.list_tenant_providers("tenant-with-no-providers")
      {:ok, []}
  """
  @callback list_tenant_providers(tenant_id :: String.t()) ::
              {:ok, [ProviderConfig.t()]} | {:error, term()}

  @doc """
  Retrieves a specific provider configuration by ID.

  ## Examples

      iex> Storage.get_provider("provider-456")
      {:ok, %Nimbus.Provider.Config{
        id: "provider-456",
        tenant_id: "tenant-123",
        ...
      }}

      iex> Storage.get_provider("nonexistent")
      {:error, :not_found}
  """
  @callback get_provider(provider_id :: String.t()) ::
              {:ok, ProviderConfig.t()} | {:error, :not_found}

  @doc """
  Retrieves the forge configuration for a tenant.

  Each tenant has exactly one forge configuration.

  ## Examples

      iex> Storage.get_tenant_forge_config("tenant-123")
      {:ok, %Nimbus.Forge.Config{
        tenant_id: "tenant-123",
        type: :github,
        ...
      }}

      iex> Storage.get_tenant_forge_config("tenant-without-forge")
      {:error, :not_found}
  """
  @callback get_tenant_forge_config(tenant_id :: String.t()) ::
              {:ok, ForgeConfig.t()} | {:error, :not_found}

  @doc """
  Returns the configured storage implementation module.

  ## Examples

      iex> Nimbus.Storage.impl()
      MyApp.NimbusStorage
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:nimbus, :storage) ||
      raise """
      No storage implementation configured for Nimbus.

      Please configure a storage implementation in your config:

          config :nimbus, :storage, MyApp.NimbusStorage

      The module must implement the Nimbus.Storage behavior.
      """
  end

  @doc """
  Delegates to the configured storage implementation's get_tenant/1.
  """
  @spec get_tenant(String.t()) :: {:ok, Tenant.t()} | {:error, :not_found}
  def get_tenant(tenant_id), do: impl().get_tenant(tenant_id)

  @doc """
  Delegates to the configured storage implementation's list_tenant_providers/1.
  """
  @spec list_tenant_providers(String.t()) :: {:ok, [ProviderConfig.t()]} | {:error, term()}
  def list_tenant_providers(tenant_id), do: impl().list_tenant_providers(tenant_id)

  @doc """
  Delegates to the configured storage implementation's get_provider/1.
  """
  @spec get_provider(String.t()) :: {:ok, ProviderConfig.t()} | {:error, :not_found}
  def get_provider(provider_id), do: impl().get_provider(provider_id)

  @doc """
  Delegates to the configured storage implementation's get_tenant_forge_config/1.
  """
  @spec get_tenant_forge_config(String.t()) :: {:ok, ForgeConfig.t()} | {:error, :not_found}
  def get_tenant_forge_config(tenant_id), do: impl().get_tenant_forge_config(tenant_id)
end
