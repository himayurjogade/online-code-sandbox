# Jenkins CI/CD Setup Guide

This directory contains the declarative Jenkins Pipeline for **Online Code Sandbox**, providing an enterprise, self-hosted alternative to GitHub Actions.

## Prerequisites & Required Jenkins Plugins

Ensure your Jenkins controller / agent has the following installed:

1. **Node.js** (v20+) with `pnpm` (v9+)
2. **Docker** and **Docker Compose** (with permissions to `/var/run/docker.sock`)
3. **Terraform** (v1.5+)
4. **Ansible** (v2.15+)

### Required Jenkins Plugins

- **Pipeline** (`workflow-aggregator`)
- **Git** (`git`)
- **SSH Agent Plugin** (`ssh-agent`)
- **Credentials Binding Plugin** (`credentials-binding`)
- **AnsiColor** (`ansicolor`)

---

## Configured Credentials

Set up these credentials in Jenkins (**Manage Jenkins ➔ Credentials**):

| Credential ID           | Kind                          | Description                                                                      |
| ----------------------- | ----------------------------- | -------------------------------------------------------------------------------- |
| `github-registry-creds` | Username with password        | GitHub Personal Access Token (PAT) with `read:packages` & `write:packages` scope |
| `aws-deploy-ssh-key`    | SSH Username with private key | SSH key for user `ubuntu` to access AWS EC2 sandbox instances                    |

---

## Pipeline Stages

```text
Parallel: Quality, Tests & IaC
  ├── Code Quality & Typecheck (pnpm check)
  ├── Unit Tests (pnpm test)
  └── IaC & Prometheus Rules (terraform validate, ansible syntax, promtool)
        │
Build & Push Docker Images (GHCR)
  ├── Services: api, worker, web
  └── Runtimes: sandbox-python, sandbox-javascript, sandbox-cpp, sandbox-c, sandbox-java
        │
E2E Integration Verification (scripts/e2e-test.sh)
        │
Approval Gate (Manual confirmation on main branch)
        │
Deploy to AWS via Ansible (infrastructure/ansible/playbook.yml)
        │
Post-Deploy Smoke Test (API & multi-language execution check)
```

---

## Setting Up the Pipeline Job

1. In Jenkins, create a **New Item** ➔ **Pipeline**.
2. Under **Pipeline Definition**, select **Pipeline script from SCM**.
3. Choose **Git**, enter repository URL `https://github.com/vinayak-jaybhaye/online-code-sandbox.git`.
4. Set Script Path to `infrastructure/jenkins/Jenkinsfile`.
5. Save and trigger **Build Now**.
