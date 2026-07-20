# Cloud-Native SRE & GitOps Platform

Welcome to my enterprise-grade SRE portfolio project! This repository is a Mono-repo designed to showcase a fully automated, secure, and observable cloud-native application deployment.

## Architecture Diagram

*(diagram goes here)*

This project is built incrementally, focusing on Site Reliability Engineering (SRE) best practices, automated quality gates, and GitOps workflows:

* **1: CI Pipeline & Docker Containerization with Security Scanning** 🟢 (Completed)
* **2: Local Kubernetes Orchestration (Kind) & Helm Charts packaging** 🟢 (Completed)
* **3: GitOps continuous delivery with ArgoCD & Sealed Secrets** 🟢 (Completed - **Current Stage**)
* **4: Observability & Monitoring (Prometheus & Grafana dashboards)** ⏳
* **5: Infrastructure as Code (IaC) with Terraform** ⏳

---

## 🛠️ Tech Stack & SRE Tools

* **Application:** FastAPI (Python 3.12), Pydantic, SQLAlchemy, PostgreSQL
* **Orchestration & Packaging:** Kubernetes, Helm v3, Kind (Kubernetes in Docker)
* **GitOps & Continuous Delivery:** ArgoCD, Bitnami Sealed Secrets
* **CI/CD:** GitHub Actions
* **Containerization:** Docker (Multi-stage builds, Bookworm slim images)
* **Security & Hardening:** Trivy CLI (Vulnerability Scans), Kubernetes Network Policies, Non-root containers, Sealed Secrets encryption
* **Quality Gates:** Black (Formatter), Ruff (Linter), Pytest & Pytest-Cov (Unit Tests & Coverage)

---

## 🟢 1st Milestone: Secure CI/CD Pipeline

The first phase of the platform is fully complete and operational. Every git push triggers a robust automated pipeline:

### 1. Code Quality & Testing
* **Linter & Formatter:** Code is strictly checked via `ruff` and `black` to maintain enterprise code styling.
* **Automated Tests:** Unit tests run automatically using `pytest`, generating test coverage reports.

### 2. Multi-stage Docker Builds
* The application is packaged into a highly optimized, multi-stage Docker image using a secure non-root base (`python:3.12-slim-bookworm`).
* Builds are extremely fast (under 25 seconds) and produce minimum-sized artifacts.

### 3. Proactive Security Scanning (Trivy CLI)
* **Filesystem Scan:** Scans the source code for exposed secrets and dependency vulnerabilities before building.
* **Container Image Scan:** Scans the final Docker image layer-by-layer for high and critical vulnerabilities.

> **SRE Implementation Note (Supply-Chain Security):** Instead of relying on a third-party GitHub Action, the pipeline installs and runs the native Trivy CLI directly on the runner. This gives complete control over the security testing environment, and lets the same scan be run identically on a developer's own machine.

> **SRE Implementation Note (Vulnerability Triage):** The pipeline uses `--ignore-unfixed`, so it only fails the build on vulnerabilities that actually have an available patch. Base-image CVEs without an upstream fix (common in any Debian/Python base image) are visible in scan output but don't block delivery — the goal is actionable signal, not noise.

---

## 🟢 2nd Milestone: Local Kubernetes & Helm Packaging (Reliability & Security Hardening)

The second phase transitions the containerized application into an enterprise-ready, self-healing Kubernetes cluster locally.

### 1. Local Kubernetes Clustering (Kind)
* Configured a lightweight local Kubernetes cluster using **Kind** (`kind-config.yaml`) with customized control-plane settings and extra port mappings (80/443) pre-configured to receive an Ingress controller in future steps.

### 2. Enterprise Helm Chart Packaging (`sre-platform-app`)
* Instead of relying on `helm create` boilerplate, the entire environment (FastAPI + Postgres) was hand-built and packaged using **Helm v3**, so every template is understood and intentional.
* Fully decoupled environment configuration from code using a centralized `values.yaml` file, allowing seamless multi-environment deployments.

### 3. High-Availability & Stateful Data (PostgreSQL StatefulSet)
* Deployed PostgreSQL using a **StatefulSet** (instead of a simple Deployment) to guarantee a stable network identity (`postgres-0`) and dedicated Persistent Volume Claims (PVC) for data durability.
* Bound the database to a **Headless Service** (`sre-platform-app-postgres-headless`) to enable reliable DNS-based pod discovery.

### 4. Zero-Trust Network Security (Network Policies)
* Enforced a strict `Default-Deny` ingress **NetworkPolicy** on the database pod.
* Explicitly allows inbound connections **only** from pods matching the FastAPI label selector, on port `5432`. All other network traffic — other namespaces, other pods, a compromised shell — is blocked.

### 5. Self-Healing & Probes (Reliability Engineering)
Three distinct health endpoints, each backing a different Kubernetes probe:
  * **Startup Probe** (`/health/startup`): gives the app time to complete schema initialization before liveness/readiness checks even begin.
  * **Liveness Probe** (`/health/live`): restarts the container if the process itself locks up. Deliberately does **not** check the database — a slow DB should never cause Kubernetes to kill an otherwise-healthy pod.
  * **Readiness Probe** (`/health/ready`): performs an active database check (`SELECT 1`). If it fails, Kubernetes stops routing traffic to that pod without restarting it.

### 6. Zero-Downtime Rollouts
* `RollingUpdate` strategy with `maxSurge: 25%` / `maxUnavailable: 0` — new pods must pass their readiness probe and start receiving traffic before any old pod is terminated.

---

## 🟢 3rd Milestone: GitOps Continuous Delivery (ArgoCD & Sealed Secrets)

The third phase replaces manual `helm install`/`helm upgrade` commands with a fully automated, self-healing GitOps workflow.

### 1. ArgoCD — Pull-Based Deployment
* ArgoCD runs **inside** the cluster and continuously watches this repository's `charts/sre-platform-app` path.
* Any change pushed to `main` is automatically detected, rendered via Helm, and applied to the cluster — no CI pipeline ever needs `kubeconfig` credentials.
* `syncPolicy.automated` is configured with:
  * `selfHeal: true` — if someone manually edits a live resource (`kubectl edit`), ArgoCD reverts it back to match Git on the next reconciliation.
  * `prune: true` — resources removed from Git are automatically removed from the cluster.
* **Verified live:** scaling the FastAPI deployment from 1 → 2 replicas was done entirely by editing `replicaCount` in `values.yaml` and pushing to Git — zero manual `kubectl`/`helm` commands touched the cluster.

### 2. Bitnami Sealed Secrets — Git-Safe Credential Management
* The PostgreSQL credentials are **never** committed as plaintext. Instead, `kubeseal` encrypts them client-side into a `SealedSecret` custom resource, which is safe to publish in a public GitHub repository.
* Only the Sealed Secrets controller running inside this specific cluster holds the private key needed to decrypt it — the ciphertext is useless to anyone without cluster access.
* On sync, the controller automatically decrypts the `SealedSecret` into a regular Kubernetes `Secret`, consumed transparently by the FastAPI and PostgreSQL pods via `secretKeyRef` — no application code or chart template needed to change.

### 3. End-to-End Verification
* `GET /health/ready` confirms live DB connectivity through the full network path (FastAPI → NetworkPolicy → headless Service → StatefulSet).
* Full CRUD cycle (`POST /users`, `GET /users`) tested successfully against the GitOps-managed deployment, confirming the entire stack — app, database, secrets, and networking — works end-to-end under ArgoCD management.

---

## 🧠 SRE Interview Notes: Key Architectural Decisions

**Why ArgoCD (GitOps/Pull) instead of deploying straight from GitHub Actions (Push)?**
> With a push model, the CI system needs the cluster's `kubeconfig` credentials — an external system holding keys to production infrastructure. With ArgoCD, the controller runs inside the cluster and only needs read access to the Git repo. No inbound firewall ports, no exposed cluster credentials, and automatic drift correction if the live state ever diverges from Git.

**Why StatefulSet instead of Deployment for PostgreSQL?**
> The database needs a stable network identity and dedicated persistent storage tied to that identity. A Deployment's pods are interchangeable; a StatefulSet's are not — `postgres-0` always gets the same PVC back, even after a restart or reschedule.

**Why three separate health endpoints instead of one?**
> Liveness and readiness answer different questions. Liveness asks "is the process alive?" — a slow database should never trigger a restart here. Readiness asks "can this pod serve traffic right now?" — an active DB check that pulls the pod out of rotation without killing it. Conflating the two causes cascading restarts during a transient database hiccup.

**Why Sealed Secrets instead of committing plaintext credentials (even for a demo project)?**
> A public GitHub repo is a public GitHub repo — habit matters more than the specific risk in a throwaway Kind cluster. Sealed Secrets means the encryption/decryption boundary is enforced by tooling, not by developer discipline, and the same pattern carries directly into a real production repo without any rework.

---

## 🏁 Repository Structure

```text
cloud-native-sre-platform/
├── .github/
│   └── workflows/
│       └── ci.yml                # Lint, test, Trivy fs+image scan
├── app/
│   ├── src/
│   │   ├── main.py                # FastAPI app, health endpoints, metrics
│   │   ├── database.py            # SQLAlchemy engine, models, DB health check
│   │   ├── metrics.py             # Prometheus counters/histograms
│   │   └── config.py              # Environment-driven settings
│   ├── tests/                     # Pytest unit tests
│   ├── Dockerfile                 # Multi-stage, non-root, hardened
│   └── requirements*.txt
├── charts/
│   └── sre-platform-app/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml    # FastAPI: probes, resources, security context
│           ├── statefulset.yaml   # PostgreSQL: PVC, probes
│           ├── service.yaml       # ClusterIP (app) + headless (postgres)
│           ├── networkpolicy.yaml # DB isolation
│           └── sealedsecret.yaml  # Encrypted DB credentials
├── argocd/
│   └── application.yaml           # GitOps Application definition
├── kind-config.yaml
└── README.md
```

---

## 🚀 Coming Next

* **Milestone 4 (Observability):** Prometheus + Grafana + Alertmanager — the Four Golden Signals, business metrics dashboards, and real-time alerting.
* **Milestone 5 (Chaos & Scaling):** Locust load testing + Horizontal Pod Autoscaler — chaos scenario demo.
* **Milestone 6 (IaC):** Terraform blueprint for cloud deployment, validated in CI without ever running `apply`.