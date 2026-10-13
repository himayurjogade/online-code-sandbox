# Online Code Sandbox

A polling-based online code execution platform. Submit Python code through a web interface, execute it securely in Docker sandboxes, and view results — all without a database.

## Architecture

```
┌─────────────┐     HTTP     ┌──────────┐   Redis Queue   ┌──────────┐   Docker   ┌─────────────┐
│   React UI  │ ──────────▶ │  Express │ ──────────────▶│  Worker  │  ────────▶│  Sandbox    │
│  (Monaco)   │ ◀────poll── │   API    │                 │          │ ◀──────── │  Container  │
└─────────────┘              └──────────┘                 └──────────┘            └─────────────┘
                                  │                            │
                                  └──────── Redis State ───────┘
```

**State machine:** `QUEUED → RUNNING → COMPLETED | TIMEOUT | RUNTIME_ERROR | OUTPUT_LIMIT | CANCELLED`

## Quick Start

```bash
# Prerequisites: Node.js 18+, pnpm, Docker

# 1. Install dependencies
pnpm install

# 2. Start full stack (API + Worker + Redis + Web)
pnpm docker:up

# 3. Open http://localhost:5173
```

### Development (individual services)

```bash
pnpm dev:api          # Express API on :3000
pnpm dev:worker       # Worker process
pnpm dev:web          # Vite dev server on :5173
```

### Code Quality

```bash
pnpm check            # lint + format:check + typecheck (run before committing)
pnpm lint             # ESLint
pnpm format           # Prettier auto-fix
pnpm typecheck        # TypeScript strict check
```

## Project Structure

```
apps/
  api/              Express REST API — receives submissions, stores state in Redis
  worker/           Job consumer — executes code in Docker sandboxes
  web/              React frontend — Monaco editor, polling-based output display
packages/
  shared/           Shared types, enums, validation (single source of truth)
docker/
  sandbox/python/   Python 3.11-slim sandbox Dockerfile
infrastructure/     Terraform (Single-Node K3s EC2), Kubernetes manifests, Ansible, Jenkins
```

## Deployment Options

- **Local Docker Compose**: `pnpm docker:up` (runs API, Worker, Redis, Web on localhost)
- **Local Kubernetes Demo (Kind)**: `./scripts/k8s-local.sh up` (runs full K8s stack on Kind)
- **AWS Single-Node Kubernetes (EC2)**: `./scripts/deploy-ec2.sh provision` (provisions 1 EC2 instance running K3s with full app and observability stack). See [infrastructure/terraform/README.md](infrastructure/terraform/README.md).

## Environment Variables

Copy `.env.example` to `.env` and adjust as needed. See the file for all available variables.

## API Endpoints

| Method | Path                         | Description                                              |
| ------ | ---------------------------- | -------------------------------------------------------- |
| POST   | `/api/executions`            | Submit code (`{ language, source }`) → `{ executionId }` |
| GET    | `/api/executions/:id`        | Get execution state (poll until terminal)                |
| POST   | `/api/executions/:id/cancel` | Request cancellation                                     |

## Design Decisions

| Decision                       | Rationale                                                    |
| ------------------------------ | ------------------------------------------------------------ |
| Redis-only state (no DB)       | Executions are ephemeral — TTL-based, no persistence needed  |
| Polling over WebSockets        | Simpler first; architecture supports additive WS upgrade     |
| `child_process` over dockerode | Fewer deps, simpler, same security model                     |
| BLPOP over Redis Streams       | Single-worker simplicity; Streams easy to adopt later        |
| Transport-agnostic services    | WebSocket handler reuses same business logic, no duplication |
| `ExecutionEngine` interface    | Swap Docker for Firecracker/gVisor without touching worker   |

## Known Limitations

- **Polling only** — no real-time streaming yet. Architecture ready for WebSocket upgrade.
- **Single worker** — no horizontal scaling yet. Redis Streams upgrade path is clear.
- **Docker socket mount** — local dev convenience. Production needs proper container runtime isolation.
- **Cancel** — marks Redis state but may not kill a running container mid-execution.
- **Python only** — multi-language support is additive (new sandbox Dockerfile + engine config).

## Future Roadmap

1. **Output streaming** — WebSocket transport, Redis Pub/Sub for real-time output
2. **Bidirectional pipeline** — stdin forwarding for interactive programs
3. **Multi-language** — JavaScript, Go, Rust sandbox containers
4. **Kubernetes** — Helm chart, horizontal worker scaling, consumer groups
5. **Observability** — Prometheus metrics, structured logging
