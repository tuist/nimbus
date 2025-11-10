# ☁️ Nimbus

Nimbus is a control plane for orchestrating infrastructure for multi-environment build and test setups on cloud providers. It manages the complete lifecycle of your infrastructure, including runners, caching, telemetry, and more.

## 📋 Overview

Nimbus acts as a central orchestration layer for managing infrastructure across cloud providers. It provides:

- **🎛️ Infrastructure Orchestration**: Centralized control plane for managing runners, cache, and telemetry across multiple cloud providers
- **☁️ Multi-Cloud Support**: Interfaces with AWS, Azure, GCP, Hetzner, and local environments
- **🔗 Git Forge Integration**: Seamless integration with GitHub, GitLab, and other Git forges
- **⚡ On-Demand Provisioning**: Dynamic environment provisioning for any workload
- **📊 Telemetry & Observability**: Built-in telemetry for monitoring infrastructure health and performance

## 🎯 Use Cases

Nimbus is ideal for organizations running multiple build and test environments that need:

- 🏢 **Multi-Environment Orchestration**: Manage infrastructure across multiple cloud providers from a single daemon
- ⏱️ **On-Demand Infrastructure**: Accept extra latency in exchange for better cost control, especially for expensive resources like macOS runners
- 💰 **Cost Optimization**: Trade elasticity for predictable costs by leveraging existing cloud provider contracts
- 📈 **Infrastructure Observability**: Centralized telemetry and monitoring for your entire infrastructure

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

