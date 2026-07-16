# Cloud-Native SRE & GitOps Platform

Welcome to my enterprise-grade SRE portfolio project! This repository is a Mono-repo designed to showcase a fully automated, secure, and observable cloud-native application deployment.

## Architecture Diagram

This project is built incrementally, focusing on Site Reliability Engineering (SRE) best practices, automated quality gates, and GitOps workflows:

* **1: CI Pipeline & Docker Containerization with Security Scanning** 🟢 (Completed)
* **2: Local Kubernetes Orchestration (Kind) & Helm Charts packaging** 🟢 (Completed - **Current Stage**)
* **3: GitOps continuous delivery with ArgoCD** ⏳
* **4: Observability & Monitoring (Prometheus & Grafana dashboards)** ⏳
* **5: Infrastructure as Code (IaC) with Terraform** ⏳

---

## 🛠️ Tech Stack & SRE Tools

* **Application:** FastAPI (Python 3.12), Pydantic, SQLAlchemy, PostgreSQL
* **Orchestration & Packaging:** Kubernetes, Helm v3, Kind (Kubernetes in Docker)
* **CI/CD:** GitHub Actions
* **Containerization:** Docker (Multi-stage builds, Bookworm slim images)
* **Security & Hardening:** Trivy CLI (Vulnerability Scans), Kubernetes Network Policies, Non-root containers
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
* **Filesystem Scan:** Scans the source code for exposed secrets and vulnerabilities before building.
* **Container Image Scan:** Scans the final Docker image layer-by-layer for high and critical vulnerabilities.

> **SRE Implementation Note (Supply-Chain Security):** During setup, instead of relying on third-party GitHub Actions (which can be vulnerable to supply-chain attacks or deprecation), the pipeline installs and runs the native Trivy CLI directly on the runner. This ensures zero Node.js deprecation warnings, maximum performance, and complete control over the security testing environment.

---

## 🟢 2nd Milestone: Local Kubernetes & Helm Packaging (Reliability & Security Hardening)

The second phase transitions the containerized application into an enterprise-ready, self-healing Kubernetes cluster locally. 

### 1. Local Kubernetes Clustering (Kind)
* Configured a lightweight local Kubernetes cluster using **Kind** (`kind-config.yaml`) with customized control-plane settings and extra port mappings (80/443) pre-configured to receive an Ingress controller in future steps.

### 2. Enterprise Helm Chart Packaging (`sre-platform-app`)
* Instead of static manifests, the entire environment (FastAPI + Postgres) was modularized and packaged using **Helm v3**.
* Fully decoupled environment configurations from code using a centralized `values.yaml` file, allowing seamless multi-environment deployments.

### 3. High-Availability & Stateful Data (PostgreSQL StatefulSet)
* Deployed PostgreSQL using a **StatefulSet** (instead of a simple Deployment) to guarantee a stable network identity (`postgres-0`) and dedicated Persistent Volume Claims (PVC) for data durability.
* Bound the database to a **Headless Service** (`sre-platform-postgres-headless`) to enable reliable DNS-based pod discovery.

### 4. Zero-Trust Network Security (Network Policies)
* Enforced a secure **NetworkPolicy** on the database namespace.
* Applied a strict `Default-Deny` ingress filter on PostgreSQL, explicitly allowing inbound connections **only** from pods matching the FastAPI label selector on port `5432`. All other network traffic is blocked.

### 5. Self-Healing & Probes (Reliability Engineering)
* Integrated standard SRE probes to handle lifecycle events:
  * **Startup Probes:** Allows PostgreSQL and FastAPI ample time to initialize without triggering premature failure restarts.
  * **Liveness Probes:** Restarts unhealthy container instances automatically if the main thread locks.
  * **Readiness Probes:** Performs a database check (`SELECT 1`) on FastAPI's `/health/ready` endpoint. The service drops traffic routing to the pod if the database connection fails, ensuring zero-downtime routing.