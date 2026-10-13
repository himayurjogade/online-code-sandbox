# Single-Node Kubernetes (K3s) on AWS EC2

This directory contains the Terraform infrastructure code to provision a **single EC2 instance** running **K3s (lightweight Kubernetes)** that hosts the entire Online Code Sandbox application and observability stack.

---

## 1. Architecture Overview

Previously, the infrastructure provisioned 4 separate EC2 instances (`redis`, `api`, `worker-1`, `worker-2`), incurring high idle costs, complex inter-node security group configurations, and operational overhead.

The simplified architecture consolidates the entire stack onto **one `t3.large` EC2 instance**:

```
                       ┌────────────────────────────────────────────────────────┐
                       │               AWS EC2 (t3.large, 40GB gp3)            │
                       │               Public IP: <server_public_ip>            │
                       │                                                        │
:80   (HTTP)   ───────>│ ┌────────────────────────────────────────────────────┐ │
:3000 (API)    ───────>│ │             K3s Single-Node Cluster                │ │
:3002 (Grafana)───────>│ │                                                    │ │
:9090 (Prom)   ───────>│ │  ┌──────────────┐         ┌────────────────────┐   │ │
                       │ │  │   Web (80)   │────────>│     API (3000)     │   │ │
                       │ │  │ LoadBalancer │         │    LoadBalancer    │   │ │
                       │ │  └──────────────┘         └─────────┬──────────┘   │ │
                       │ │                                     │              │ │
                       │ │                                     ▼              │ │
                       │ │                             ┌───────────────┐      │ │
                       │ │                             │  Redis (6379) │      │ │
                       │ │                             │   ClusterIP   │      │ │
                       │ │                             │(PVC: 2GB /data)      │ │
                       │ │                             └───────▲───────┘      │ │
                       │ │                                     │              │ │
                       │ │  ┌──────────────┐                   │              │ │
                       │ │  │ Worker Pods  │───────────────────┘              │ │
                       │ │  │ (2 replicas) │                                  │ │
                       │ │  └──────┬───────┘                                  │ │
                       │ │         │ (hostPath: /var/run/docker.sock)         │ │
                       │ │         ▼                                          │ │
                       │ │  ┌───────────────────────────────────────────────┐ │ │
                       │ │  │         Host Docker Engine (CE)               │ │ │
                       │ │  │      (Pre-pulled Sandbox Containers)          │ │ │
                       │ │  └───────────────────────────────────────────────┘ │ │
                       │ │                                                    │ │
                       │ │  ┌──────────────┐         ┌────────────────────┐   │ │
                       │ │  │ Grafana(3002)│────────>│ Prometheus (9090)  │   │ │
                       │ │  │ LoadBalancer │         │(PVC: 5GB /promdata)│   │ │
                       │ │  └──────────────┘         └────────────────────┘   │ │
                       │ └────────────────────────────────────────────────────┘ │
                       └────────────────────────────────────────────────────────┘
```

### Key Architectural Highlights:

1. **Single Node**: Exactly 1 EC2 instance running Ubuntu 24.04 LTS.
2. **K3s with Klipper ServiceLB**: K3s binds Kubernetes `type: LoadBalancer` services directly to the host's public ports (Web on 80, API on 3000, Grafana on 3002, Prometheus on 9090).
3. **Internal Security**: Redis (port 6379) is only exposed internally via `ClusterIP` within the Kubernetes network; it is **never** reachable from the public internet.
4. **Direct Sandbox Execution**: The host runs Docker CE. The worker pod mounts `/var/run/docker.sock` to launch ephemeral sandbox containers (`sandbox-python`, `sandbox-javascript`, etc.) on the host engine.
5. **Persistent Volumes**: Local-path storage class in K3s provides persistent storage for Redis (`2Gi`) and Prometheus (`5Gi`), surviving pod restarts.
6. **Zero-Touch Cloud-Init**: The EC2 instance provisions, installs Docker & K3s, and deploys all workloads automatically on first boot.

---

## 2. Resource Requirements & AWS Cost Comparison

| Metric                                    | Original 4-Instance Setup                                                   | New Single-Node K3s Setup                     |
| :---------------------------------------- | :-------------------------------------------------------------------------- | :-------------------------------------------- |
| **Compute Instances**                     | 4 instances (1x `t3.small` Redis, 1x `t3.small` API, 2x `t3.small` Workers) | **1 instance (`t3.large`, 2 vCPU, 8 GB RAM)** |
| **Memory Allocation**                     | 8 GB total across 4 machines                                                | 8 GB unified memory pool                      |
| **Storage**                               | 4x 20 GB EBS gp3 = 80 GB                                                    | **1x 40 GB EBS gp3**                          |
| **Elastic IPs / NAT**                     | Multiple IPs / subnets                                                      | **1 Public IP**                               |
| **Approx. Monthly Cost (AWS ap-south-1)** | ~$60 - $75 / month                                                          | **~$30 - $35 / month (~50% cost reduction)**  |

---

## 3. Prerequisites

- **AWS CLI** installed and configured with appropriate credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).
- **Terraform** >= 1.0.0.
- An existing AWS Key Pair in your chosen region (default: `builder_key`).

---

## 4. Provisioning & Deployment

You can provision the single EC2 instance using the automated script or directly using Terraform.

### Option A: Using the Helper Script (Recommended)

From the project root:

```bash
# Provision instance and wait for health checks to pass
./scripts/deploy-ec2.sh provision

# Check live endpoint reachability
./scripts/deploy-ec2.sh status

# Run end-to-end multi-language test suite against deployed server
./scripts/deploy-ec2.sh test

# Tear down infrastructure when done
./scripts/deploy-ec2.sh destroy
```

### Option B: Using Terraform Directly

```bash
cd infrastructure/terraform

# Initialize Terraform (uses S3 remote backend)
terraform init

# Review execution plan (verify exactly 1 instance)
terraform plan

# Apply infrastructure
terraform apply
```

Terraform outputs will display:

```
server_public_ip = "13.233.xxx.xxx"
web_url          = "http://13.233.xxx.xxx"
api_url          = "http://13.233.xxx.xxx:3000"
grafana_url      = "http://13.233.xxx.xxx:3002"
prometheus_url   = "http://13.233.xxx.xxx:9090"
```

Cloud-init bootstrap will automatically configure Docker, K3s, and apply workloads within 2–3 minutes of initial instance launch.

---

## 5. Accessing Services

Once deployed, access the endpoints using the instance's public IP:

- **Web Frontend**: `http://<SERVER_IP>/`
- **REST API**: `http://<SERVER_IP>:3000/api/health`
- **Grafana Dashboard**: `http://<SERVER_IP>:3002/` (Default credentials: `admin` / `admin`)
- **Prometheus UI**: `http://<SERVER_IP>:9090/`

---

## 6. Inspecting Pods and Troubleshooting

SSH into the single instance using your key:

```bash
ssh -i ~/.ssh/builder_key.pem ubuntu@<SERVER_IP>
```

Once inside the instance:

```bash
# View all running pods in the sandbox namespace
kubectl get pods -n sandbox -o wide

# View services and port mappings
kubectl get svc -n sandbox

# Inspect pod logs
kubectl logs -n sandbox -l app=api -f
kubectl logs -n sandbox -l app=worker -f
kubectl logs -n sandbox -l app=redis -f

# Check cloud-init provisioning logs (if initial startup is in progress)
tail -f /var/log/cloud-init-output.log
```

---

## 7. Redeploying & Updating Workloads

If you make changes to application images or Kubernetes manifests:

### Via Ansible:

From your local machine or CI/CD runner:

```bash
ansible-playbook -i infrastructure/ansible/inventory.ini infrastructure/ansible/playbook.yml
```

### Directly on the Instance:

```bash
ssh ubuntu@<SERVER_IP> "cd /home/ubuntu/online-code-sandbox && git pull && k3s kubectl apply -k infrastructure/k8s"
```

---

## 8. Persistent Data Storage

- **Storage Class**: K3s uses the default Rancher `local-path` provisioner.
- **Redis State**: Stored on PVC `redis-data` (2Gi) mounted at `/data`. Dump snapshots persist across pod restarts and instance reboots.
- **Prometheus Metrics**: Stored on PVC `prometheus-data` (5Gi) mounted at `/prometheus`. Historical scrape metrics persist across pod restarts.
- **Host Location**: Data resides physically on the EC2 root EBS volume at `/var/lib/rancher/k3s/storage/`.
- **Termination Warning**: Because the storage is backed by the instance's EBS volume, destroying the EC2 instance with `terraform destroy` will delete persistent state unless EBS snapshots are retained.

---

## 9. Known Limitations

1. **Single Point of Failure (SPOF)**: As a single-node setup, instance failure, termination, or hardware degradation will cause downtime. Multi-AZ high availability is intentionally omitted to keep costs minimal.
2. **Local Docker Socket**: Worker pods share `/var/run/docker.sock` with the host. This is optimal for dev/demo setups but production multi-tenant environments would benefit from Firecracker microVMs or gVisor runtimes.
3. **Horizontal Worker Scaling**: Workers can be scaled vertically or horizontally up to the resource capacity of the `t3.large` instance (2 vCPUs / 8 GB RAM). For heavy workloads, increase the instance type to `t3.xlarge` in `variables.tf`.
