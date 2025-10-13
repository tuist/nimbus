# Nimbus Development Plan

## Overview

Nimbus is an Elixir library for provisioning and managing CI runner environments. It integrates with cloud providers (AWS, Hetzner, etc.) and Git forges (GitHub, GitLab, Forgejo) to create on-demand runner infrastructure.

## Architecture

### Core Principles

1. **Storage Abstraction**: The integrating application provides storage implementation via behaviors
2. **Multi-tenant**: Each tenant has their own providers, forge configuration, and machines
3. **Unified Machine Model**: Abstract away provider-specific details (e.g., AWS dedicated hosts)
4. **Telemetry-driven**: Emit events for all significant operations that integrators can subscribe to
5. **Lean State**: Minimize stored data - prefer querying cloud provider APIs with tags

### Module Structure

```
Nimbus
├── Nimbus.Application
├── Nimbus.Storage (behavior - implemented by integrator)
│   ├── get_tenant(tenant_id)
│   ├── list_tenant_providers(tenant_id)
│   └── get_tenant_forge_config(tenant_id)
├── Nimbus.CloudProvider (behavior)
│   ├── Nimbus.CloudProvider.AWS (Phase 1)
│   └── Nimbus.CloudProvider.Hetzner (Future)
├── Nimbus.Forge
│   ├── Nimbus.Forge.GitHub (Phase 1)
│   ├── Nimbus.Forge.GitLab (Future)
│   └── Nimbus.Forge.Forgejo (Future)
├── Nimbus.Machine
│   ├── Nimbus.Machine.Provisioner
│   ├── Nimbus.Machine.Lifecycle
│   └── Nimbus.Machine.SSH
└── Nimbus.Telemetry
```

### Data Models

#### Tenant
```elixir
%Tenant{
  id: "tenant-123",
  name: "Acme Corp"
}
```

#### Provider Configuration
```elixir
%ProviderConfig{
  id: "provider-456",
  tenant_id: "tenant-123",
  type: :aws,  # :aws, :hetzner, :gcp, :azure
  credentials: %{
    access_key_id: "AKIA...",
    secret_access_key: "..."
  },
  config: %{
    region: "us-east-1",
    tags: %{"managed_by" => "nimbus"}
  }
}
```

#### Forge Configuration
```elixir
%ForgeConfig{
  tenant_id: "tenant-123",
  type: :github,  # :github, :gitlab, :forgejo
  credentials: %{
    # GitHub App
    app_id: "123456",
    installation_id: "789012",
    private_key: "-----BEGIN RSA PRIVATE KEY-----..."
    # Or for GitLab/Forgejo
    # token: "glpat-..."
  },
  org: "tuist"  # or group/instance URL for GitLab/Forgejo
}
```

#### Machine
```elixir
%Machine{
  id: "machine-uuid",
  tenant_id: "tenant-123",
  provider_id: "provider-456",

  # Unified fields
  os: :macos,  # :macos, :linux
  arch: :arm64,  # :arm64, :x86_64
  state: :ready,  # :provisioning, :image_installing, :ready, :running, :stopping, :terminated
  ip_address: "1.2.3.4",
  ssh_public_key: "ssh-rsa ...",
  labels: ["macos", "xcode-15"],

  # Image configuration (optional - nil for machines without images)
  image: %{
    id: "ami-123abc",  # AMI ID, Docker image name, etc.
    type: :ami,  # :ami | :docker | nil
    state: :ready,  # :provisioning | :ready
    installed_at: ~U[2025-01-15 10:30:00Z]
  },

  # Timestamps (queried from provider, not stored)
  created_at: ~U[2025-01-15 10:00:00Z],

  # Provider-specific metadata
  provider_metadata: %{
    instance_id: "i-123abc",
    host_id: "h-456def",  # AWS Mac only
    minimum_allocation_hours: 24  # Provider-specific
  }
}
```

**Notes**:
- Machine `state` includes `:image_installing` to track image setup progress
- `image` field tracks software configuration (AMIs for macOS, Docker for Linux)
- Linux machines with pre-built images transition directly to `:ready`
- macOS machines go through `:provisioning` → `:image_installing` → `:ready`
- Future: May extend to support multiple VMs per physical machine (2 VMs/Mac limit)

### Storage Behavior Contract

The integrating application implements:

```elixir
defmodule Nimbus.Storage do
  @callback get_tenant(tenant_id :: String.t()) ::
    {:ok, Tenant.t()} | {:error, :not_found}

  @callback list_tenant_providers(tenant_id :: String.t()) ::
    {:ok, [ProviderConfig.t()]} | {:error, term()}

  @callback get_provider(provider_id :: String.t()) ::
    {:ok, ProviderConfig.t()} | {:error, :not_found}

  @callback get_tenant_forge_config(tenant_id :: String.t()) ::
    {:ok, ForgeConfig.t()} | {:error, :not_found}
end
```

### Cloud Provider Behavior

Each cloud provider implements:

```elixir
defmodule Nimbus.CloudProvider do
  @callback provision(provider_config :: ProviderConfig.t(), specs :: map()) ::
    {:ok, Machine.t()} | {:error, term()}

  @callback terminate(provider_config :: ProviderConfig.t(), machine :: Machine.t()) ::
    :ok | {:error, term()}

  @callback can_terminate?(machine :: Machine.t()) ::
    {:ok, true} | {:error, :minimum_allocation_period, hours_remaining: integer()}

  @callback list_machines(provider_config :: ProviderConfig.t(), tenant_id :: String.t()) ::
    {:ok, [Machine.t()]} | {:error, term()}

  @callback get_machine(provider_config :: ProviderConfig.t(), machine_id :: String.t()) ::
    {:ok, Machine.t()} | {:error, term()}
end
```

### Machine Lifecycle Flow

```
1. Tenant requests machine via Nimbus.provision_machine/2
   ├─> Validate tenant and provider
   ├─> Get provider credentials from storage
   └─> Call CloudProvider.provision/2

2. CloudProvider provisions infrastructure
   AWS Mac: Allocate dedicated host → Launch instance
   AWS Linux: Launch instance
   Hetzner: Create server
   ├─> Tag with tenant_id for discovery
   └─> Return Machine struct

3. Nimbus.Machine.Lifecycle sets up runner
   ├─> Wait for machine to be accessible
   ├─> SSH into machine (using tenant's SSH key)
   ├─> Install dependencies (homebrew, etc.)
   ├─> Download Git forge runner agent
   ├─> Get registration token from Forge API
   ├─> Register runner with forge
   └─> Emit telemetry: [:nimbus, :machine, :ready]

4. Runner operates (managed by Git forge)
   ├─> Forge assigns jobs
   └─> Runner executes jobs

5. Tenant requests termination via Nimbus.terminate_machine/2
   ├─> Check can_terminate? (24h minimum for AWS Mac)
   ├─> Unregister runner from forge
   ├─> Terminate instance (and release host if needed)
   └─> Emit telemetry: [:nimbus, :machine, :terminated]
```

### Telemetry Events

Nimbus emits telemetry events for all significant operations:

```elixir
# Machine lifecycle
[:nimbus, :machine, :provision_start]
[:nimbus, :machine, :provision_success]
[:nimbus, :machine, :provision_failure]
[:nimbus, :machine, :setup_start]
[:nimbus, :machine, :setup_success]
[:nimbus, :machine, :setup_failure]
[:nimbus, :machine, :ready]
[:nimbus, :machine, :terminate_start]
[:nimbus, :machine, :terminate_success]
[:nimbus, :machine, :terminate_failure]

# Forge operations
[:nimbus, :forge, :register_runner_start]
[:nimbus, :forge, :register_runner_success]
[:nimbus, :forge, :register_runner_failure]
[:nimbus, :forge, :unregister_runner_start]
[:nimbus, :forge, :unregister_runner_success]
[:nimbus, :forge, :unregister_runner_failure]

# Cloud provider operations
[:nimbus, :cloud_provider, :api_call_start]
[:nimbus, :cloud_provider, :api_call_success]
[:nimbus, :cloud_provider, :api_call_failure]

# SSH operations
[:nimbus, :ssh, :connect_start]
[:nimbus, :ssh, :connect_success]
[:nimbus, :ssh, :connect_failure]
[:nimbus, :ssh, :command_start]
[:nimbus, :ssh, :command_success]
[:nimbus, :ssh, :command_failure]
```

Each event includes metadata like `tenant_id`, `machine_id`, `duration`, `error`, etc.

## Phase 1: MVP

### Scope

**Cloud Provider**: AWS EC2 Mac (mac2.metal on dedicated hosts)
**Git Forge**: GitHub (via GitHub App)
**Machine Management**: Manual provisioning/termination by tenant
**Features**: Basic lifecycle, 24h minimum tracking, SSH-based setup

### Implementation Tasks

#### 1. Core Infrastructure
- [ ] Set up Nimbus.Application supervision tree (deferred - not needed for MVP)
- [x] Define Storage behavior and contracts
- [x] Define Provider behavior (renamed from CloudProvider)
- [x] Implement Nimbus.Machine struct and core functions
- [x] Set up telemetry with :telemetry library
- [x] Implement Local provider for development/testing
- [x] Add MuonTrap for process management

#### 2. AWS Provider
- [ ] Implement Nimbus.CloudProvider.AWS
- [ ] Handle EC2 dedicated host allocation
- [ ] Handle mac2.metal instance provisioning
- [ ] Tag resources with tenant_id and nimbus metadata
- [ ] Implement machine discovery via AWS API
- [ ] Implement can_terminate? with 24h check
- [ ] Handle host + instance cleanup

#### 3. GitHub Forge Integration
- [ ] Implement GitHub App authentication
- [ ] Implement runner registration token API
- [ ] Implement runner registration API
- [ ] Implement runner unregistration API
- [ ] Handle API errors and retries

#### 4. Machine Setup (SSH)
- [ ] Implement Nimbus.Machine.SSH module
- [ ] SSH connection with tenant's key
- [ ] Install homebrew and dependencies
- [ ] Download and install GitHub runner agent
- [ ] Configure and register runner
- [ ] Health check and verification

#### 5. Public API
- [x] `Nimbus.provision_machine(tenant_id, provider_id, specs)`
- [x] `Nimbus.terminate_machine(tenant_id, machine_id)` (with TODO: provider lookup)
- [x] `Nimbus.list_machines(tenant_id)`
- [x] `Nimbus.get_machine(tenant_id, machine_id)` (with TODO: provider lookup)
- [x] `Nimbus.can_terminate_machine?(tenant_id, machine_id)` (with TODO: provider lookup)

#### 6. Testing
- [ ] Unit tests for core modules
- [ ] Mocked AWS API tests
- [ ] Mocked GitHub API tests
- [ ] Integration tests (may require real AWS/GitHub sandbox)
- [ ] SSH command execution tests

#### 7. Documentation
- [ ] Module documentation (@moduledoc)
- [ ] Function documentation (@doc)
- [ ] Integration guide for host applications
- [ ] Storage behavior implementation guide
- [ ] Configuration examples

### Dependencies

```elixir
# mix.exs dependencies
{:ex_aws, "~> 2.5"},
{:ex_aws_ec2, "~> 2.0"},
{:hackney, "~> 1.18"},
{:jason, "~> 1.4"},
{:telemetry, "~> 1.2"},
{:req, "~> 0.4"},  # For GitHub API
{:sshex, "~> 2.2"},  # For SSH operations
{:nimble_options, "~> 1.1"}  # For config validation
```

## Phase 2: Enhanced Features

### Warm Pools
- [ ] Pre-provision N machines per tenant/provider
- [ ] Maintain minimum pool size
- [ ] Automatic replenishment
- [ ] Pool sizing strategies

### Additional Cloud Providers
- [ ] Hetzner dedicated servers
- [ ] AWS EC2 Linux instances
- [ ] GCP (future)
- [ ] Azure (future)

### Additional Git Forges
- [ ] GitLab (via personal access token or OAuth)
- [ ] Forgejo (similar to GitLab)

### Automatic Lifecycle Management
- [ ] Auto-terminate idle machines (after minimum period)
- [ ] Auto-provision based on queue depth
- [ ] Cost optimization strategies
- [ ] Usage analytics and reporting

### Advanced Features
- [ ] Machine health monitoring
- [ ] Automatic recovery from failures
- [ ] Runner agent updates
- [ ] Multi-region support
- [ ] Cost tracking and budgets

## Completed

### Project Setup
- [x] Set up mise.toml with lockfile enabled
- [x] Created Elixir application structure using mix
- [x] Created CLAUDE.md and README.md documentation
- [x] Designed architecture and data models
- [x] Set up Quokka (code formatter/linter) and Mimic (mocking library)
- [x] Configured .formatter.exs with Quokka plugin
- [x] Generated .credo.exs configuration
- [x] Updated CLAUDE.md with development workflow and pre-commit checklist

### Core Infrastructure (Phase 1)
- [x] Define core data structures (Tenant, Provider.Config, Forge.Config, Machine)
- [x] Define Nimbus.Storage behavior with delegation functions
- [x] Define Nimbus.Provider behavior with delegation functions
- [x] Implement Nimbus.Provider.Local for development/testing
- [x] Set up Nimbus.Telemetry with event helpers and convenience macro
- [x] Add telemetry dependency (~> 1.2)
- [x] Add MuonTrap for process management (~> 1.5)
- [x] Implement public API (Nimbus module) with provision/terminate/list/get functions

## In Progress

## Open Questions

1. **SSH Key Management**: Should we support multiple SSH keys per tenant for different purposes?
2. **GitHub Runner Scope**: Organization-level vs repository-level runners?
3. **Error Handling**: Retry strategies for transient failures (AWS API throttling, SSH timeouts)?
4. **Logging**: Use Logger or rely purely on telemetry?
5. **Machine Naming**: Convention for naming machines/runners (e.g., "nimbus-{tenant}-{uuid}")?
6. **macOS VM Concurrency Limits**:
   - **Legal/Licensing**: Apple's EULA restricts macOS virtualization - only allowed on Apple hardware, and with specific conditions:
     - macOS can be virtualized on Apple Silicon using macOS 12.0.1+ (Virtualization.framework)
     - Up to 2 VM instances per physical Mac
     - Each VM requires a separate license
   - **AWS EC2 Mac Limitations**: AWS mac2.metal is bare metal (not virtualized), so Apple's 2-VM limit doesn't apply. However:
     - 24-hour minimum allocation per dedicated host
     - One instance per host (bare metal)
     - No concurrent VMs on same host - each tenant gets full dedicated host
   - **Question**: Do we need to track/enforce any concurrency limits per tenant? Or rely on AWS account limits?
7. **macOS Image Management**:
   - **Problem**: Unlike Linux (Docker images), macOS images are installed separately:
     - AWS provides AMIs (Amazon Machine Images) with pre-installed macOS versions
     - Additional software (Xcode, simulators) must be installed after provisioning via SSH
     - Images are large (50GB+) and installation is slow (30+ minutes for Xcode)
   - **Modeling Approach** (DECIDED):
     - **Option A (MVP)**: Add `image_id` to specs, track image lifecycle in Machine struct
       ```elixir
       specs = %{
         os: :macos,
         arch: :arm64,
         image_id: "ami-123abc",  # macOS 14.2 base
         image_type: :ami,
         setup_script: "install_xcode_15.sh"  # Run via SSH after provision
       }

       # Machine struct tracks image state
       %Machine{
         state: :image_installing,  # or :ready when complete
         image: %{
           id: "ami-123abc",
           type: :ami,
           state: :provisioning,  # transitions to :ready
           installed_at: nil
         }
       }
       ```
   - **Design Decision**:
     - Machine struct now includes `image` field to track software configuration
     - New machine state: `:image_installing` (between `:provisioning` and `:ready`)
     - Linux: Can transition directly to `:ready` (pre-built images)
     - macOS: Goes through image installation phase (Xcode, etc.)
   - **Future**: Can split into separate Host/VM concepts when supporting 2 VMs per physical Mac
   - **Question**: Should we cache/reuse provisioned machines with software pre-installed (warm pool), or always provision fresh?

## Notes

### AWS EC2 Mac Specifics
- AWS Mac dedicated hosts have 24-hour minimum allocation (billing constraint)
- Bare metal instances (mac2.metal, mac2-m2.metal, mac2-m2pro.metal)
- One instance per dedicated host (no concurrent VMs)
- Uses Nitro System but not virtualized - direct hardware access
- Must allocate dedicated host first, then launch instance on that host

### macOS Licensing & Virtualization
- Apple's EULA: macOS virtualization only on Apple hardware
- Maximum 2 concurrent VMs per physical Mac (using Virtualization.framework)
- AWS EC2 Mac is compliant (bare metal on Apple hardware)
- Each macOS instance requires separate license

### Image Management
- macOS images distributed as AMIs (Amazon Machine Images)
- Base OS only - additional software installed post-provision
- Large images (50GB+) with slow installation times (30+ min for Xcode)
- Xcode includes: IDE, SDKs, simulators, command-line tools (~40GB installed)

### Architecture Notes
- Machine discovery uses cloud provider tags instead of storing state
- Integrator provides storage implementation and SSH keys
- Nimbus manages complete lifecycle including forge integration

