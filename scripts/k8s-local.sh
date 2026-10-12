#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="online-code-sandbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${ROOT_DIR}/infrastructure/k8s"

ensure_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi

  echo "==> Tool '$tool' not found in PATH."
  mkdir -p "$HOME/.local/bin"
  export PATH="$HOME/.local/bin:$PATH"

  if [ "$tool" = "kubectl" ]; then
    echo "==> Downloading standalone kubectl to ~/.local/bin/kubectl ..."
    local k8s_version
    k8s_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -Lo "$HOME/.local/bin/kubectl" "https://dl.k8s.io/release/${k8s_version}/bin/linux/amd64/kubectl"
    chmod +x "$HOME/.local/bin/kubectl"
    echo "==> kubectl installed successfully to ~/.local/bin/kubectl"
  elif [ "$tool" = "kind" ]; then
    echo "==> Downloading standalone kind to ~/.local/bin/kind ..."
    curl -Lo "$HOME/.local/bin/kind" "https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64"
    chmod +x "$HOME/.local/bin/kind"
    echo "==> kind installed successfully to ~/.local/bin/kind"
  else
    echo "ERROR: Please install $tool manually." >&2
    exit 1
  fi
}

cmd_up() {
  echo "=== Starting Kubernetes Local Demo Cluster ==="
  ensure_tool "docker"
  ensure_tool "kind"
  ensure_tool "kubectl"

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running." >&2
    exit 1
  fi

  if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
    echo "==> Kind cluster '${CLUSTER_NAME}' already exists."
  else
    echo "==> Creating Kind cluster '${CLUSTER_NAME}' with port mappings & docker.sock mount..."
    kind create cluster --name "${CLUSTER_NAME}" --config "${K8S_DIR}/kind-config.yaml"
  fi

  echo "==> Applying Kubernetes manifests..."
  kubectl apply -k "${K8S_DIR}"

  echo "==> Waiting for Redis rollout..."
  kubectl rollout status deployment/redis -n sandbox --timeout=90s

  echo "==> Waiting for API rollout..."
  kubectl rollout status deployment/api -n sandbox --timeout=120s

  echo "==> Waiting for Worker rollout..."
  kubectl rollout status deployment/worker -n sandbox --timeout=120s

  echo "==> Waiting for Web rollout..."
  kubectl rollout status deployment/web -n sandbox --timeout=120s

  echo ""
  echo "============================================================"
  echo "🎉 Local Kubernetes Demo Cluster is UP and RUNNING!"
  echo "============================================================"
  echo "  • Web Frontend: http://localhost:8080"
  echo "  • API Server:   http://localhost:3000/api/health"
  echo "============================================================"
  echo "To view cluster pods:  kubectl get pods -n sandbox"
  echo "To run E2E tests:     ./scripts/k8s-local.sh test"
  echo "To tear down cluster: ./scripts/k8s-local.sh down"
  echo "============================================================"
}

cmd_down() {
  echo "=== Tearing Down Kubernetes Local Demo Cluster ==="
  if command -v kind >/dev/null 2>&1; then
    if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
      kind delete cluster --name "${CLUSTER_NAME}"
      echo "==> Cluster '${CLUSTER_NAME}' deleted successfully."
    else
      echo "==> Cluster '${CLUSTER_NAME}' is not running."
    fi
  else
    echo "Kind is not installed; nothing to delete."
  fi
}

cmd_status() {
  ensure_tool "kubectl"
  echo "=== Sandbox Kubernetes Cluster Status ==="
  kubectl get pods,svc -n sandbox -o wide
}

cmd_test() {
  echo "=== Running E2E Verification Against Local K8s Cluster ==="
  "${ROOT_DIR}/scripts/e2e-test.sh" "http://localhost:3000"
}

case "${1:-}" in
  up)
    cmd_up
    ;;
  down)
    cmd_down
    ;;
  status)
    cmd_status
    ;;
  test)
    cmd_test
    ;;
  *)
    echo "Usage: $0 {up|down|status|test}"
    exit 1
    ;;
esac
