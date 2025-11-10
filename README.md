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

### mise + UBI (Recommended)

The easiest way to install and run Nimbus is using [mise](https://mise.jdx.dev/) with the UBI backend:

```bash
# Install and run the latest version
mise x ubi:tuist/nimbus@latest -- nimbus start

# Or install globally
mise use -g ubi:tuist/nimbus@latest
nimbus start
```

### Docker

```bash
docker pull ghcr.io/tuist/nimbus:latest
docker run -p 4000:4000 ghcr.io/tuist/nimbus:latest
```

### Native Binaries

Download pre-built binaries from the [latest release](https://github.com/tuist/nimbus/releases/latest):

- **macOS (Apple Silicon)**: `nimbus-macos-aarch64.tar.gz`
- **macOS (Intel)**: `nimbus-macos-x86_64.tar.gz`
- **Linux (x86_64)**: `nimbus-linux-x86_64.tar.gz`
- **Linux (ARM64)**: `nimbus-linux-aarch64.tar.gz`

Extract and run:

```bash
tar xzf nimbus-*.tar.gz
./nimbus_*/bin/nimbus start
```

### As a Library

If you're integrating Nimbus into an Elixir application, add it to your dependencies in `mix.exs`:

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

