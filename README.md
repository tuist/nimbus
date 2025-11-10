# ☁️ Nimbus

Nimbus is a daemon that provisions and manages the infrastructure (runners, cache, and more) for build systems and test runners to operate optimally. It acts as a glue layer between Git forges and cloud providers, enabling teams to run their builds efficiently on any cloud infrastructure.

## 📋 Overview

Nimbus provides standalone value as an open-source tool for infrastructure management, while creating a natural pathway to Tuist's managed offerings. Similar to how Grafana Cloud hosts Grafana instances, Tuist can host Nimbus daemons while also supporting self-hosted deployments.

Key features:

- **🔗 Git Forge Integration**: Connects with GitHub, GitLab, Forgejo, and other Git forges
- **☁️ Multi-Cloud Support**: Interfaces with AWS, GCP, Hetzner, and local environments
- **⚡ Elastic Infrastructure**: On-demand provisioning of runners, cache, and supporting infrastructure
- **🎯 Build Optimization**: Designed to help build systems and test runners operate at peak efficiency
- **🏠 Flexible Deployment**: Can be self-hosted or managed by Tuist
- **🔒 Per-Tenant Isolation**: Each tenant runs their own isolated Nimbus daemon process

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

