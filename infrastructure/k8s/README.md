# Kubernetes Local Demo

This directory contains Kubernetes manifests and configuration for running the **Online Code Sandbox** stack on a local Kubernetes cluster (e.g. using [Kind](https://kind.sigs.k8s.io/) or [Minikube](https://minikube.sigs.k8s.io/)).

> **Note**: This setup is strictly isolated on branch `feat/k8s-local-demo` for local demonstrations and testing, and does not alter the production AWS infrastructure or GitHub Actions workflows.

---

## Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │             Kind Cluster               │
                      │                                        │
                      │  ┌───────────┐         ┌────────────┐  │
:8080 (Host Port) ───>│  │  Web Pod  │────────>│  API Pods  │  │<─── :3000 (Host Port)
                      │  │ (NodePort)│         │ (NodePort) │  │
                      │  └───────────┘         └─────┬──────┘  │
                      │                              │         │
                      │                              ▼         │
                      │                        ┌───────────┐   │
                      │                        │ Redis Pod │   │
                      │                        │(ClusterIP)│   │
                      │                        └─────▲─────┘   │
                      │                              │         │
                      │  ┌────────────┐              │         │
                      │  │Worker Pods │──────────────┘         │
                      │  │(2 replicas)│                        │
                      │  └─────┬──────┘                        │
                      └────────┼───────────────────────────────┘
                               │ (hostPath: /var/run/docker.sock)
                               ▼
                    [ Host Docker Daemon ]
                   (Runs Sandbox Containers)
```

### Components

1. **`namespace.yaml`**: Dedicated `sandbox` namespace.
2. **`redis/`**: Deployment + ClusterIP Service (`redis.sandbox.svc.cluster.local:6379`).
3. **`api/`**: 2-replica Deployment with liveness & readiness health probes, exposed via Service port 3000 (NodePort 30000).
4. **`worker/`**: 2-replica Deployment mounting `/var/run/docker.sock` via `hostPath` to execute user sandbox code.
5. **`web/`**: 1-replica React + Vite frontend exposed via Service port 80 (NodePort 30080).
6. **`kind-config.yaml`**: Kind cluster configuration with port mappings (30080 -> 8080, 30000 -> 3000) and Docker socket passthrough.

---

## Quick Start (One Command)

To start the local Kubernetes demo cluster:

```bash
./scripts/k8s-local.sh up
```

_(If `kind` or `kubectl` are not yet installed in your PATH, the script will automatically install standalone binaries to `~/.local/bin/`)._

### Accessing the Applications

- **Web Frontend**: [http://localhost:8080](http://localhost:8080)
- **API Health Check**: [http://localhost:3000/api/health](http://localhost:3000/api/health)

### Running Verification Tests

To run the automated multi-language end-to-end test suite against the local Kubernetes cluster:

```bash
./scripts/k8s-local.sh test
```

### Viewing Cluster Status

```bash
./scripts/k8s-local.sh status
# or
kubectl get pods,svc -n sandbox
```

### Tearing Down the Cluster

```bash
./scripts/k8s-local.sh down
```

---

## AWS Single-Node EC2 Kubernetes Deployment

The exact same Kubernetes manifests in this directory are deployed to a single AWS EC2 instance running K3s via Terraform and cloud-init:

```bash
# Provision single EC2 instance and bootstrap K3s cluster
./scripts/deploy-ec2.sh provision

# Check live remote status
./scripts/deploy-ec2.sh status

# Run automated end-to-end tests
./scripts/deploy-ec2.sh test

# Destroy EC2 instance
./scripts/deploy-ec2.sh destroy
```

See [infrastructure/terraform/README.md](../terraform/README.md) for full architecture and operational details.
