#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/infrastructure/terraform"
ANSIBLE_DIR="${ROOT_DIR}/infrastructure/ansible"

get_server_ip() {
  if [ -f "${ANSIBLE_DIR}/inventory.ini" ]; then
    grep -A 1 '\[server\]' "${ANSIBLE_DIR}/inventory.ini" | grep -v '\[server\]' | awk '{print $1}' | head -n 1
  else
    (cd "$TF_DIR" && terraform output -raw server_public_ip 2>/dev/null || true)
  fi
}

get_ssh_opts() {
  local key=""
  for candidate in "${SSH_KEY:-}" "$HOME/keys/builder_key.pem" "$HOME/.ssh/builder_key.pem" "$HOME/.ssh/id_rsa"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      key="$candidate"
      break
    fi
  done
  if [ -n "$key" ]; then
    echo "-i $key -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
  else
    echo "-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
  fi
}

cmd_provision() {
  echo "=========================================================="
  echo "🚀 Provisioning Single-Node Kubernetes (K3s) on AWS EC2"
  echo "=========================================================="

  if ! command -v terraform >/dev/null 2>&1; then
    echo "ERROR: Terraform binary not found in PATH." >&2
    exit 1
  fi

  cd "$TF_DIR"
  echo "==> Initializing Terraform..."
  terraform init

  echo "==> Applying Terraform (Provisioning 1 EC2 Instance)..."
  terraform apply -auto-approve

  echo ""
  SERVER_IP=$(terraform output -raw server_public_ip 2>/dev/null || true)
  if [ -z "$SERVER_IP" ]; then
    echo "ERROR: Could not retrieve server public IP from Terraform output." >&2
    exit 1
  fi

  echo "=========================================================="
  echo "🎉 EC2 Instance Provisioned Successfully!"
  echo "=========================================================="
  echo "  • Server Public IP:   $SERVER_IP"
  echo "  • Web Frontend:       http://${SERVER_IP}"
  echo "  • API Server:         http://${SERVER_IP}:3000"
  echo "  • Grafana Dashboard:  http://${SERVER_IP}:3002"
  echo "  • Prometheus UI:      http://${SERVER_IP}:9090"
  echo "=========================================================="
  echo ""
  echo "==> Cloud-init is currently bootstrapping Docker, K3s, and workloads on the instance."
  echo "==> Polling http://${SERVER_IP}:3000/api/health until application is ready..."

  local ssh_opts
  ssh_opts=$(get_ssh_opts)

  local max_attempts=45
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://${SERVER_IP}:3000/api/health" >/dev/null 2>&1; then
      echo ""
      echo "✅ Cluster is UP and application is HEALTHY!"
      echo "You can now open http://${SERVER_IP} in your browser."
      return 0
    fi

    # If SSH is reachable, ensure latest local manifests are synced & applied
    if [ $attempt -eq 12 ] || [ $attempt -eq 24 ]; then
      if ssh $ssh_opts ubuntu@"$SERVER_IP" "command -v k3s >/dev/null 2>&1" 2>/dev/null; then
        echo -n " [Syncing manifests] "
        ssh $ssh_opts ubuntu@"$SERVER_IP" "mkdir -p /home/ubuntu/online-code-sandbox/infrastructure" 2>/dev/null || true
        scp $ssh_opts -r "${ROOT_DIR}/infrastructure/k8s" "ubuntu@${SERVER_IP}:/home/ubuntu/online-code-sandbox/infrastructure/" 2>/dev/null || true
        ssh $ssh_opts ubuntu@"$SERVER_IP" "k3s kubectl apply -k /home/ubuntu/online-code-sandbox/infrastructure/k8s" 2>/dev/null || true
      fi
    fi

    echo -n "."
    sleep 6
    attempt=$((attempt + 1))
  done

  echo ""
  echo "⚠️ Note: Application health check timed out. Cloud-init may still be completing."
  echo "Check status with: ./scripts/deploy-ec2.sh status"
}

cmd_status() {
  local server_ip
  server_ip=$(get_server_ip)
  if [ -z "$server_ip" ]; then
    echo "ERROR: Server IP not found. Has infrastructure been provisioned?" >&2
    exit 1
  fi

  echo "=== Single-Node Kubernetes EC2 Server Status ==="
  echo "Server IP: $server_ip"
  echo ""
  echo "Checking endpoint reachability:"
  echo -n "  • Web (port 80):    "
  curl -s -f -o /dev/null -w "%{http_code}\n" "http://${server_ip}" 2>/dev/null || echo "Not reachable yet"
  echo -n "  • API (port 3000):  "
  curl -s -f -o /dev/null -w "%{http_code}\n" "http://${server_ip}:3000/api/health" 2>/dev/null || echo "Not reachable yet"
  echo -n "  • Grafana (3002):   "
  curl -s -f -o /dev/null -w "%{http_code}\n" "http://${server_ip}:3002/api/health" 2>/dev/null || echo "Not reachable yet"
  echo -n "  • Prometheus (9090):"
  curl -s -f -o /dev/null -w "%{http_code}\n" "http://${server_ip}:9090/-/healthy" 2>/dev/null || echo "Not reachable yet"

  echo ""
  local ssh_opts
  ssh_opts=$(get_ssh_opts)
  if ssh $ssh_opts ubuntu@"$server_ip" "command -v k3s >/dev/null 2>&1" 2>/dev/null; then
    echo "=== Running Pods on Cluster ==="
    ssh $ssh_opts ubuntu@"$server_ip" "k3s kubectl get pods -n sandbox -o wide" 2>/dev/null || true
  else
    echo "To inspect live pods directly via SSH:"
    echo "  ssh ubuntu@$server_ip 'kubectl get pods -n sandbox -o wide'"
  fi
}


cmd_test() {
  local server_ip
  server_ip=$(get_server_ip)
  if [ -z "$server_ip" ]; then
    echo "ERROR: Server IP not found. Has infrastructure been provisioned?" >&2
    exit 1
  fi

  echo "=== Running E2E Verification Suite Against EC2 Cluster ==="
  "${ROOT_DIR}/scripts/e2e-test.sh" "http://${server_ip}:3000"
}

cmd_destroy() {
  echo "=========================================================="
  echo "⚠️ Destroying Single-Node EC2 Kubernetes Infrastructure"
  echo "=========================================================="
  cd "$TF_DIR"
  terraform destroy -auto-approve
  echo "==> Infrastructure destroyed successfully."
}

case "${1:-}" in
  provision)
    cmd_provision
    ;;
  status)
    cmd_status
    ;;
  test)
    cmd_test
    ;;
  destroy)
    cmd_destroy
    ;;
  *)
    echo "Usage: $0 {provision|status|test|destroy}"
    exit 1
    ;;
esac
