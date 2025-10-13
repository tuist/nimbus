# Nimbus - Claude Context

## Overview

Nimbus is an Elixir runtime application that provisions and manages environments as CI runners. It acts as a glue layer between Git forges (like GitHub, GitLab) and cloud providers, enabling on-demand environment provisioning for continuous integration workloads.

## Purpose

Nimbus powers "Tuist Runners" and is integrated into the Tuist server (https://github.com/tuist/tuist). It provides a flexible, storage-agnostic architecture that allows the integrating application to provide its own storage implementation.

## Key Characteristics

- **Cloud Provider Integration**: Interfaces with various cloud providers to provision CI runner environments
- **Git Forge Integration**: Connects with Git forges to receive and process CI job requests
- **Storage Abstraction**: Expects the integrating application to provide storage implementation
- **On-Demand Provisioning**: Provisions environments on the fly as needed

## Target Use Cases

Nimbus is ideal for companies that:

1. **Accept Extra Latency**: Are comfortable with the latency involved in provisioning environments on demand
2. **Prefer Cost Control over Speed**: Especially relevant for macOS runners where elasticity can be traded for better cost control
3. **Have Cloud Provider Contracts**: Want to reuse existing contracts with cloud providers like AWS

## Architecture

- **Type**: Elixir application library
- **Integration Model**: Embedded into host applications (like Tuist server)
- **Storage**: Abstracted - provided by the integrating application
- **Runtime**: Elixir/OTP for reliability and concurrency

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