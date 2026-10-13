#!/usr/bin/env bash
set -euxo pipefail

LOG_FILE="/var/log/sandbox-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================================="
echo "🚀 Bootstrapping Single-Node Kubernetes (K3s) on EC2"
echo "Started at: $(date -u)"
echo "=========================================================="

# 1. Expand root partition if needed
echo "==> Expanding filesystem..."
growpart /dev/nvme0n1 1 || growpart /dev/xvda 1 || true
resize2fs /dev/nvme0n1p1 || resize2fs /dev/root || resize2fs /dev/xvda1 || true

# 2. Install baseline dependencies
echo "==> Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends git curl jq

# 3. Install Docker CE (for Worker Docker-in-Docker sandbox execution)
echo "==> Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
usermod -aG docker ubuntu

# 4. Pull and tag sandbox runner images on host Docker daemon
echo "==> Pulling sandbox runner images into host Docker..."
for lang in python javascript cpp c java; do
  echo "Pulling sandbox-$${lang}..."
  docker pull "ghcr.io/vinayak-jaybhaye/sandbox-$${lang}:latest" || true
  docker tag "ghcr.io/vinayak-jaybhaye/sandbox-$${lang}:latest" "sandbox-$${lang}:latest" || true
done

# 5. Install K3s (Single-Node Lightweight Kubernetes)
echo "==> Installing K3s..."
# Disable Traefik so port 80 maps directly to our web frontend service
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --disable traefik" sh -

echo "==> Waiting for K3s node to be Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do
  echo "Waiting for K3s node to register and become Ready..."
  sleep 3
done

# Setup kubeconfig and aliases for ubuntu user
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

grep -q "KUBECONFIG" /home/ubuntu/.bashrc || echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc
grep -q "alias kubectl" /home/ubuntu/.bashrc || echo 'alias kubectl="k3s kubectl"' >> /home/ubuntu/.bashrc

# 6. Clone or update application repository
echo "==> Setting up application repository..."
APP_DIR="/home/ubuntu/online-code-sandbox"
if [ ! -d "$APP_DIR" ]; then
  git clone https://github.com/vinayak-jaybhaye/online-code-sandbox.git "$APP_DIR"
fi

cd "$APP_DIR"
git fetch origin || true
git checkout "${app_revision}" 2>/dev/null || true
if [ ! -d "$APP_DIR/infrastructure/k8s" ]; then
  git checkout feat/k8s-local-demo 2>/dev/null || true
fi
chown -R ubuntu:ubuntu "$APP_DIR"

# 7. Deploy Kubernetes manifests
echo "==> Applying Kubernetes manifests..."
k3s kubectl apply -k "$APP_DIR/infrastructure/k8s"

# 8. Wait for deployments to become healthy
echo "==> Waiting for core workloads to roll out..."
k3s kubectl rollout status deployment/redis -n sandbox --timeout=180s || true
k3s kubectl rollout status deployment/api -n sandbox --timeout=180s || true
k3s kubectl rollout status deployment/worker -n sandbox --timeout=180s || true
k3s kubectl rollout status deployment/web -n sandbox --timeout=180s || true
k3s kubectl rollout status deployment/prometheus -n sandbox --timeout=180s || true
k3s kubectl rollout status deployment/grafana -n sandbox --timeout=180s || true

echo "=========================================================="
echo "🎉 Bootstrap finished successfully at $(date -u)!"
echo "=========================================================="
touch /var/log/sandbox-bootstrap.done
