# devops-desk

A terminal-based DevOps control center. One CLI entry point — `devops-desk` — that unifies AWS SSO, EKS, Kubernetes, FluxCD, Helm, Terraform (tfctl), OCI registries, and GitHub into a fast, keyboard-driven shell workflow.

**Stack:** pure Bash + fzf. No build step, no runtime beyond the tools listed.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Environment management](#environment-management)
  - [Authentication](#authentication)
  - [Kubernetes navigation](#kubernetes-navigation)
  - [Pod operations](#pod-operations)
  - [Flux GitOps](#flux-gitops)
  - [Helm](#helm)
  - [Terraform (tfctl)](#terraform-tfctl)
  - [OCI registry](#oci-registry)
  - [GitHub](#github)
  - [Dashboard](#dashboard)
  - [k9s](#k9s)
- [FZF keyboard shortcuts](#fzf-keyboard-shortcuts)
- [Architecture](#architecture)
- [Extending devops-desk](#extending-devops-desk)
- [State & persistence](#state--persistence)
- [Uninstall](#uninstall)

---

## Features

| Feature | Description |
|---------|-------------|
| **Multi-environment** | Switch between dev / stage / prod with a single fzf picker; state persists across sessions |
| **AWS SSO** | Login, status, and logout via `aws sso` |
| **EKS connect** | `aws eks update-kubeconfig` with the right profile & region in one command |
| **FZF navigator** | Browse pods, deployments, services, namespaces, Helm releases, Flux resources, OCI registries — all in one interactive pane with live previews |
| **Pod operations** | Stream logs, exec into a shell, restart deployments, port-forward, run a debug diagnosis |
| **Flux GitOps** | Reconcile, suspend/resume kustomizations and HelmReleases; browse image policies and automations |
| **Helm** | Interactive upgrade and rollback with history preview |
| **Terraform via tfctl** | Reconcile, replan, suspend, resume Flux-managed Terraform stacks |
| **OCI registries** | Browse registries discovered from Flux OCI sources or custom URLs; drill down to tags and manifests; pull artifacts; sign/verify images with cosign |
| **GitHub integration** | Browse PRs, workflow runs, and issues with fzf; open browser, checkout, merge, rerun directly from the list |
| **Live dashboard** | Terminal overview of pod health, deployment status, Flux kustomization/HelmRelease health, image updates, and Helm releases — auto-refreshes every 30 s |
| **k9s integration** | Launches k9s with devops-desk plugins and Tokyo Night theme always injected |
| **Production safety** | All destructive operations on `prod` require an explicit `y` confirmation with a red warning banner |

---

## Requirements

### Required

| Tool | Purpose |
|------|---------|
| `bash` >= 4.x | Shell runtime |
| `aws` CLI | AWS SSO auth and EKS kubeconfig |
| `kubectl` | All Kubernetes operations |
| `fzf` | Interactive navigation everywhere |

### Optional (features degrade gracefully when missing)

| Tool | Purpose |
|------|---------|
| `k9s` | Full-featured Kubernetes TUI |
| `flux` | FluxCD GitOps operations |
| `helm` | Helm upgrade / rollback |
| `gh` | GitHub CLI — PRs, workflow runs, issues |
| `tfctl` | Flux-managed Terraform stacks |
| `oras` | OCI registry operations |
| `cosign` | Container image signing and verification |
| `bat` | Syntax-highlighted previews in fzf panes |
| `stern` | Multi-pod log streaming |
| `jq` | Pretty-print OCI manifests |

Install on macOS:

```bash
brew install awscli kubectl fzf k9s fluxcd/tap/flux helm gh tfctl oras cosign bat stern jq
```

---

## Installation

### Via Makefile (recommended)

```bash
git clone https://github.com/afeldman/devops-desk.git
cd devops-desk

# Checks required deps, copies to /opt/devops-desk, links to /usr/local/bin
make install
```

### Via install script

```bash
./install.sh
```

### Custom prefix

```bash
make install PREFIX=/usr/local/share/devops-desk BIN_DIR=/usr/local/bin
```

After installation `devops-desk` is available system-wide.

---

## Configuration

Each environment lives in its own file under `config/envs/`. Three examples are provided: `dev.sh`, `stage.sh`, `prod.sh`.

```bash
# config/envs/dev.sh
export DD_AWS_PROFILE="dev"          # AWS CLI profile name
export DD_AWS_REGION="eu-west-1"     # AWS region
export DD_EKS_CLUSTER="dev-eks"      # EKS cluster name
export DD_EKS_CLUSTER_ALIAS="dev"    # Human-readable alias (optional)

# Optional: set a default namespace
# export DD_NAMESPACE="default"

# Optional: additional OCI registries for `devops-desk nav oci`
# Registries from Flux OCI sources are auto-discovered.
# export DD_OCI_REGISTRIES="ghcr.io/myorg,123456789.dkr.ecr.eu-west-1.amazonaws.com"
```

Copy and adapt for each environment:

```bash
cp config/envs/dev.sh config/envs/my-env.sh
vim config/envs/my-env.sh
```

New environment files are picked up **automatically** — no code changes needed.

---

## Usage

### Environment management

```bash
devops-desk env              # fzf picker to select active environment
devops-desk env dev          # select directly without fzf
devops-desk status           # show current env, AWS auth state, and k8s context
```

The selected environment is saved to `~/.devops-desk/state` and reused in every subsequent command.

### Authentication

```bash
devops-desk auth             # same as auth login
devops-desk auth login       # aws sso login + verify identity
devops-desk auth status      # show current caller identity
devops-desk auth logout      # aws sso logout
```

### Kubernetes navigation

`devops-desk nav` opens an fzf root menu. Each resource type has inline action bindings (see [FZF keyboard shortcuts](#fzf-keyboard-shortcuts)).

```bash
devops-desk nav              # interactive root menu
devops-desk nav pods         # browse all pods
devops-desk nav deployments  # browse deployments
devops-desk nav services     # browse services
devops-desk nav namespaces   # switch namespace (persisted to state)
devops-desk nav helm         # browse Helm releases
devops-desk nav flux         # browse Flux resources
devops-desk nav nodes        # view cluster nodes
devops-desk nav oci          # browse OCI registries
```

After selecting a namespace with `devops-desk nav namespaces`, all subsequent `nav` commands scope to that namespace automatically. Use `devops-desk nav namespaces` again to switch or scope back to `--all-namespaces`.

### Pod operations

```bash
devops-desk pods             # interactive menu
devops-desk pods logs        # stream logs (picks container if multi-container pod)
devops-desk pods restart     # restart a deployment (with rollout wait)
devops-desk pods exec        # shell into a pod (tries bash, falls back to sh)
devops-desk pods forward     # port-forward to a pod or service
devops-desk pods debug       # run a full diagnosis (status, events, describe, recent logs)
```

### Flux GitOps

```bash
devops-desk flux             # interactive menu
devops-desk flux reconcile   # trigger reconciliation (interactive resource picker or pass args directly)
devops-desk flux status      # show kustomizations, HelmReleases, and sources with ready status
devops-desk flux images      # show image update automations, policies, and repositories
devops-desk flux suspend     # suspend a kustomization or HelmRelease (multi-select with TAB)
devops-desk flux resume      # resume suspended resources
```

Pass arguments directly to skip the picker:

```bash
devops-desk flux reconcile kustomization my-app -n flux-system
```

### Helm

```bash
devops-desk helm             # interactive menu
devops-desk helm upgrade     # select release -> enter chart version -> confirm upgrade
devops-desk helm rollback    # select release -> view history -> enter revision -> rollback
```

Both commands display live previews of current values and history inside fzf.

### Terraform (tfctl)

Manages Flux-controller-managed Terraform stacks via `tfctl`.

```bash
devops-desk tfctl            # interactive menu
devops-desk tfctl status     # list all terraform resources in flux-system
devops-desk tfctl reconcile  # trigger reconciliation for a stack
devops-desk tfctl replan     # trigger a replan
devops-desk tfctl suspend    # suspend a stack
devops-desk tfctl resume     # resume a suspended stack
```

Pass the stack name directly to skip the prompt:

```bash
devops-desk tfctl reconcile my-stack
```

### OCI registry

Discovers registries from Flux OCI sources automatically, or accepts a custom URL.

```bash
devops-desk nav oci          # browse registries -> repos -> tags -> manifest
devops-desk oras             # interactive menu
devops-desk oras login       # authenticate with a registry
devops-desk oras list        # list artifacts (oras discover)
devops-desk oras pull        # pull artifact to a local directory
devops-desk oras push        # push artifact files to a registry
devops-desk oras sign        # sign a container image with cosign
devops-desk oras verify      # verify a signed image
```

### GitHub

Requires `gh` to be authenticated (`gh auth login`).

```bash
devops-desk github           # interactive menu
devops-desk github prs       # browse open PRs (open browser / checkout / merge from fzf)
devops-desk github runs      # browse workflow runs (view logs / rerun from fzf)
devops-desk github issues    # browse open issues (open browser from fzf)
```

### Dashboard

```bash
devops-desk dashboard
```

Renders a live terminal overview:

- **Pods** — running / pending / failing counts, lists failing pods
- **Deployments** — ready / degraded counts, lists degraded deployments
- **Flux** — kustomization and HelmRelease sync status
- **Flux image updates** — latest image per policy
- **Helm** — deployed / failed release counts

Press `r` to refresh manually. Auto-refreshes every 30 seconds. Press `q` to quit.

Environment name is highlighted: green for dev, yellow for stage, red for prod.

### k9s

```bash
devops-desk k9s
```

Copies `k9s/plugins.yaml` and `k9s/skin.yaml` (Tokyo Night theme) into `~/.config/k9s/` before launching k9s, so your plugins and theme are always current.

---

## FZF keyboard shortcuts

All fzf panes share a consistent set of global bindings:

| Key | Action |
|-----|--------|
| `Ctrl+/` | Toggle preview pane |
| `Ctrl+F` | Scroll preview down |
| `Ctrl+B` | Scroll preview up |

Resource-specific bindings are shown in the fzf header line. Common bindings:

### Pods navigator (`devops-desk nav pods`)

| Key | Action |
|-----|--------|
| `Ctrl+L` | Stream logs (`kubectl logs -f`) |
| `Ctrl+E` | Exec into pod shell |
| `Ctrl+D` | Describe pod (full output in pager) |
| `Ctrl+R` | Restart owning deployment |
| `Ctrl+F` | Port-forward (prompts for ports) |
| `Ctrl+X` | Delete pod |

### Deployments navigator (`devops-desk nav deployments`)

| Key | Action |
|-----|--------|
| `Ctrl+R` | Rollout restart + wait |
| `Ctrl+S` | Scale (prompts for replica count) |
| `Ctrl+H` | Rollout history |
| `Ctrl+D` | Describe |
| `Ctrl+I` | Show container images |

### Services navigator (`devops-desk nav services`)

| Key | Action |
|-----|--------|
| `Ctrl+D` | Describe service |
| `Ctrl+F` | Port-forward |
| `Ctrl+E` | Show endpoints |

### Namespaces navigator (`devops-desk nav namespaces`)

| Key | Action |
|-----|--------|
| `Ctrl+D` | Describe namespace |
| `Ctrl+P` | List pods in namespace |
| `Enter` | Switch to namespace (persisted) |

### Flux kustomization / HelmRelease navigator

| Key | Action |
|-----|--------|
| `Ctrl+R` | Reconcile |
| `Ctrl+S` | Suspend |
| `Ctrl+U` | Resume |
| `Ctrl+D` | Describe |

### Helm navigator (`devops-desk nav helm`)

| Key | Action |
|-----|--------|
| `Ctrl+H` | Release history |
| `Ctrl+V` | Show current values |
| `Ctrl+R` | Rollback to previous revision |

### Nodes navigator (`devops-desk nav nodes`)

| Key | Action |
|-----|--------|
| `Ctrl+D` | Describe node |
| `Ctrl+P` | List pods on node |
| `Ctrl+T` | `kubectl top node` |

### GitHub PRs

| Key | Action |
|-----|--------|
| `Ctrl+O` | Open in browser |
| `Ctrl+C` | Checkout branch |
| `Ctrl+M` | Merge (squash) |

### GitHub workflow runs

| Key | Action |
|-----|--------|
| `Ctrl+O` | Open in browser |
| `Ctrl+L` | View logs in pager |
| `Ctrl+R` | Rerun workflow |

### OCI tag browser

| Key | Action |
|-----|--------|
| `Ctrl+P` | Pull artifact |
| `Ctrl+C` | Copy full image reference to clipboard |

---

## Architecture

```
bin/
  devops-desk           # Entry point: sources lib/, sets DD_FZF_OPTS, dispatches to commands/

lib/
  core.sh               # Color helpers, info/success/error/step printers
                        # require_env() - sources active env file, exits if none set
                        # confirm()     - prompts y/N; shows red banner on prod
  state.sh              # Key=value store in ~/.devops-desk/state
                        # Persists ENVIRONMENT and NAMESPACE across sessions
  checks.sh             # check_dependency(tool) and check_all_deps()

commands/
  auth.sh               # AWS SSO login / status / logout
  connect.sh            # aws eks update-kubeconfig
  nav.sh                # FZF navigator (pods / deployments / services / namespaces
                        #               / helm / flux / nodes / oci)
  flux.sh               # flux reconcile / status / images / suspend / resume
  helm.sh               # helm upgrade / rollback
  pods.sh               # logs / restart / exec / forward / debug
  dashboard.sh          # live terminal dashboard
  github.sh             # gh prs / runs / issues with fzf bindings
  tfctl.sh              # tfctl reconcile / replan / suspend / resume / status
  oras.sh               # oras login / list / pull / push + cosign sign / verify

config/envs/
  dev.sh                # DD_AWS_PROFILE, DD_AWS_REGION, DD_EKS_CLUSTER, ...
  stage.sh
  prod.sh

k9s/
  plugins.yaml          # k9s plugin definitions (copied to ~/.config/k9s/ on launch)
  skin.yaml             # Tokyo Night colour scheme
```

### Key design patterns

**Lazy loading** — command files are `source`d on first use, not at startup. Startup time is independent of the number of commands.

**Environment contract** — every command that needs AWS or Kubernetes calls `require_env`, which sources the active env file and exports `DD_*` variables. If no environment is set, the command exits with a clear message.

**Persistent state** — `~/.devops-desk/state` is a plain `KEY=value` file. `state_set`/`state_get` helpers update it atomically via a temp file.

**FZF consistency** — `DD_FZF_OPTS` is exported from the entry point so every fzf invocation inherits the same colours, border, layout, and global key bindings.

**Production safety** — `confirm()` always shows a red `PRODUCTION ENVIRONMENT` banner when `$ENVIRONMENT == prod` and requires explicit `y` input.

---

## Extending devops-desk

### Add a new environment

1. Create `config/envs/<name>.sh` with at minimum `DD_AWS_PROFILE`, `DD_AWS_REGION`, `DD_EKS_CLUSTER`.
2. The new environment appears automatically in `devops-desk env`.

No code changes needed.

### Add a new command

1. Create `commands/<name>.sh` with a `cmd_<name>()` entry function.
2. Add a `case` entry in `main()` in `bin/devops-desk`:

```bash
mycommand) source "$DEVOPS_DESK_ROOT/commands/mycommand.sh"; cmd_mycommand "$@" ;;
```

3. Optionally add it to the `usage()` function.

Use `step`, `info`, `success`, `error`, `warning` from `lib/core.sh` for consistent output. Call `require_env` if the command needs AWS/k8s context.

---

## State & persistence

devops-desk stores a small state file at `~/.devops-desk/state`:

```
ENVIRONMENT=dev
NAMESPACE=my-namespace
```

- **`ENVIRONMENT`** — set by `devops-desk env`, read by `require_env` in every command
- **`NAMESPACE`** — set by `devops-desk nav namespaces`, used by `nav` to scope kubectl queries

To reset:

```bash
rm ~/.devops-desk/state
```

---

## Uninstall

```bash
make uninstall
```

This removes `/opt/devops-desk` and `/usr/local/bin/devops-desk`. Your state file (`~/.devops-desk/`) is not removed.

```bash
# Remove state directory too
rm -rf ~/.devops-desk
```

---

## Repository

[https://github.com/afeldman/devops-desk](https://github.com/afeldman/devops-desk)
