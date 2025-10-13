# ☁️ Nimbus

Nimbus is an Elixir runtime application that provisions and manages environments as CI runners. It acts as a glue layer between Git forges (GitHub, GitLab, etc.) and cloud providers, enabling on-demand environment provisioning for continuous integration workloads.

## 📋 Overview

Nimbus powers [Tuist Runners](https://github.com/tuist/tuist) and is designed as a library that integrates into host applications. It provides:

- **☁️ Cloud Provider Integration**: Interfaces with various cloud providers to provision CI runner environments
- **🔗 Git Forge Integration**: Connects with Git forges to receive and process CI job requests
- **💾 Storage Abstraction**: Flexible architecture that expects the integrating application to provide storage implementation
- **⚡ On-Demand Provisioning**: Dynamic environment provisioning for cost-effective CI/CD

## 🎯 Use Cases

Nimbus is ideal for organizations that:

- ⏱️ Accept the extra latency of provisioning environments on the fly
- 💰 Prefer trading elasticity for better cost control (especially relevant for macOS runners)
- 🤝 Want to reuse existing contracts with cloud providers like AWS

## 🏗️ Architecture

Nimbus is designed as an embeddable Elixir application library with storage abstraction. The integrating application (such as the Tuist server) provides the storage implementation, allowing Nimbus to remain flexible and adaptable to different infrastructure setups.

## 📦 Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `nimbus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nimbus, "~> 0.1.0"}
  ]
end
```

## 🛠️ Development

This project uses [mise](https://mise.jdx.dev/) for tool version management. Install the required tools with:

```bash
mise install
```

Run tests:

```bash
mix test
```

## 📚 Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc):

```bash
mix docs
```

## 🔗 Related Projects

- [Tuist](https://github.com/tuist/tuist) - The main project that integrates Nimbus

