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
  echo "=== Starting Kubernetes Local Demo Cluster with Autoscaling & Observability ==="
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

  echo "==> Applying Metrics Server in kube-system namespace..."
  kubectl delete deployment metrics-server -n sandbox 2>/dev/null || true
  kubectl apply -f "${K8S_DIR}/metrics-server/metrics-server.yaml"

  echo "==> Applying Kubernetes manifests (Apps + Observability + HPA)..."
  kubectl apply -k "${K8S_DIR}"

  echo "==> Waiting for Redis rollout..."
  kubectl rollout status deployment/redis -n sandbox --timeout=90s

  echo "==> Waiting for API rollout..."
  kubectl rollout status deployment/api -n sandbox --timeout=120s

  echo "==> Waiting for Worker rollout..."
  kubectl rollout status deployment/worker -n sandbox --timeout=120s

  echo "==> Waiting for Web rollout..."
  kubectl rollout status deployment/web -n sandbox --timeout=120s

  echo "==> Waiting for Prometheus rollout..."
  kubectl rollout status deployment/prometheus -n sandbox --timeout=90s

  echo "==> Waiting for Grafana rollout..."
  kubectl rollout status deployment/grafana -n sandbox --timeout=90s

  echo ""
  echo "============================================================"
  echo "🎉 Local Kubernetes Demo Cluster is UP with GRAFANA & HPA!"
  echo "============================================================"
  echo "  • Web Frontend:       http://localhost:8080"
  echo "  • API Server:         http://localhost:3000/api/health"
  echo "  • Grafana Dashboard:  http://localhost:3002 (User: admin / Pass: admin)"
  echo "  • HPA Policies:       API (2->6 pods), Worker (2->8 pods)"
  echo "============================================================"
  echo "Commands:"
  echo "  • View status & HPA:   ./scripts/k8s-local.sh status"
  echo "  • Run E2E suite:       ./scripts/k8s-local.sh test"
  echo "  • Connect to Grafana:  ./scripts/k8s-local.sh grafana"
  echo "  • Simulate load spike: ./scripts/k8s-local.sh load 50"
  echo "  • Tear down cluster:   ./scripts/k8s-local.sh down"
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
  echo "=== Sandbox Kubernetes Cluster Pods & Services ==="
  kubectl get pods,svc -n sandbox -o wide
  echo ""
  echo "=== Horizontal Pod Autoscaler (HPA) Status ==="
  kubectl get hpa -n sandbox || true
}

cmd_test() {
  echo "=== Running E2E Verification Against Local K8s Cluster ==="
  "${ROOT_DIR}/scripts/e2e-test.sh" "http://localhost:8080"
}

cmd_grafana() {
  ensure_tool "kubectl"
  echo "=== Port-forwarding Grafana to http://localhost:3002 ==="
  echo "Open http://localhost:3002 in your browser (Anonymous Admin login enabled)."
  kubectl port-forward -n sandbox svc/grafana 3002:3000
}

cmd_load() {
  local count="${2:-60}"
  ensure_tool "kubectl"
  echo "=== Generating Load Spike ($count concurrent code executions) ==="
  echo "Initial Pods & HPA:"
  kubectl get hpa -n sandbox || true
  kubectl get pods -n sandbox -l 'app in (api,worker)'
  echo ""
  echo "Firing $count concurrent requests to http://localhost:8080/api/executions..."
  for i in $(seq 1 "$count"); do
    curl -s -X POST "http://localhost:8080/api/executions" \
      -H "Content-Type: application/json" \
      -d '{"language":"python","source":"import time; sum(i*i for i in range(1000000))"}' \
      > /dev/null &
  done
  wait
  echo "All $count execution requests submitted!"
  echo ""
  echo "Watching HPA autoscaling responses (Press Ctrl+C to stop watching):"
  kubectl get hpa -n sandbox -w
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
  grafana)
    cmd_grafana
    ;;
  load)
    cmd_load "$@"
    ;;
  *)
    echo "Usage: $0 {up|down|status|test|grafana|load [count]}"
    exit 1
    ;;
esac
