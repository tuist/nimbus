# Nimbus - Claude Context

## Overview

Nimbus is a standalone Elixir daemon that provisions and manages elastic CI runners. It acts as a glue layer between Git forges (like GitHub, GitLab) and cloud providers, enabling on-demand environment provisioning for continuous integration workloads.

## Purpose

Nimbus provides standalone value as an open-source tool for elastic self-hosted runners, while creating a natural pathway to Tuist's managed offerings. Similar to how Grafana Cloud hosts Grafana instances, Tuist can host Nimbus daemons while also supporting self-hosted deployments.

## Key Characteristics

- **Standalone Value**: Useful on its own for elastic CI runners on any cloud provider
- **Per-Tenant Daemon**: Each tenant runs their own isolated Nimbus daemon process
- **Flexible Deployment**: Can be self-hosted or managed by Tuist
- **Cloud Provider Integration**: Interfaces with various cloud providers (AWS, GCP, Hetzner, etc.)
- **Git Forge Integration**: Connects with Git forges (GitHub, GitLab, Forgejo)
- **Optional UI**: Control plane UI available in hosted mode, optional for self-hosted

## Deployment Models

### Stage 1: Self-Hosted (Open Source)
Users run Nimbus daemon on their infrastructure, managing everything themselves. Value: Cost savings and flexibility using their cloud provider contracts.

### Stage 2: Managed Control Plane (Tuist Premium)
Tuist hosts and manages the Nimbus daemon and provides UI. Users bring their own cloud credentials. Value: Less operational burden, monitoring, and optimization recommendations.

### Stage 3: Fully Managed (Tuist Cloud)
Tuist provides complete infrastructure - users just consume runners. Value: Zero-config CI runners with no infrastructure management.

### Stage 4: Premium Platform (Tuist Enterprise)
Full Tuist platform including runners, caching, build insights, and optimization. Value: Complete build optimization solution.

## Target Use Cases

Nimbus is ideal for:

1. **Teams with Cloud Contracts**: Want to use AWS/GCP/Azure credits for CI runners
2. **Multi-Forge Users**: Need runners across GitHub, GitLab, and self-hosted forges
3. **Cost-Conscious Teams**: Prefer cost control over maximum speed (especially macOS)
4. **Infrastructure Control**: Want self-hosted runners without manual maintenance

## Architecture

- **Type**: Standalone Elixir daemon (one per tenant)
- **Deployment**: Can run standalone or orchestrated by Tuist control plane
- **API**: RESTful API for control plane integration and management
- **Storage**: Per-daemon SQLite or provided storage connection string
- **Runtime**: Elixir/OTP for reliability, concurrency, and efficient resource usage
- **Hibernation**: Inactive daemons can hibernate to reduce costs (~$0.10/tenant/month)

## Project Structure

This is an Elixir Mix application with the standard structure:
- `lib/` - Application source code
- `test/` - Test suite
- `mix.exs` - Project configuration and dependencies

## Development

The project uses mise for tool version management. See `mise.toml` for configured tools.

### Code Quality Tools

**Quokka** - Automatic code formatter and style fixer
- Quokka is configured as a formatter plugin in `.formatter.exs`
- Run `mix format` to automatically fix code style issues based on Credo rules
- **IMPORTANT**: Before considering any work complete, you MUST run `mix format` to ensure code quality and consistency
- Quokka relies on Credo configurations and can automatically rewrite code to fix style issues

**Mimic** - Mocking library for tests
- Mimic is configured in `test/test_helper.exs` for mocking behaviors
- Use Mimic to mock the `Nimbus.Storage` and `Nimbus.Provider` behaviors in tests
- Example usage:
  ```elixir
  test "example test with mocking" do
    Nimbus.Storage
    |> expect(:get_tenant, fn "tenant-123" ->
      {:ok, %Tenant{id: "tenant-123"}}
    end)

    # Your test code
  end
  ```

**MuonTrap** - Process management for system commands
- MuonTrap is used instead of `System.cmd` for executing external commands
- Provides better process cleanup, resource management, and timeout handling
- **IMPORTANT**: Always use `MuonTrap.cmd/3` instead of `System.cmd/3` when executing shell commands
- Used primarily in `Nimbus.Provider.Local` for local command execution
- Documentation: https://hexdocs.pm/muontrap/readme.html
- Example usage:
  ```elixir
  case MuonTrap.cmd("sh", ["-c", command], into: "", stderr_to_stdout: true, timeout: 60_000) do
    {output, 0} -> {:ok, output}
    {_output, exit_code} -> {:error, exit_code}
  end
  ```

### Pre-commit Checklist

Before committing or considering work complete:
1. Run `mix format` to apply Quokka formatting
2. Run `mix test` to ensure all tests pass
3. Run `mix compile --warnings-as-errors` to ensure compilation succeeds with no warnings
4. Review changes carefully as Quokka can modify code behavior
5. Keep the PLAN.md up to date as you progress

**IMPORTANT**: All three commands must pass successfully before work is considered complete:
- `mix format` - Code formatting
- `mix test` - All tests passing
- `mix compile --warnings-as-errors` - Clean compilation without warnings