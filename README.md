# Cloud-Native SRE & GitOps Platform

Welcome to my enterprise-grade SRE portfolio project! This repository is a **Mono-repo** designed to showcase a fully automated, secure, 
and observable cloud-native application deployment.

---

## Architecture Diagram

This project is built incrementally, focusing on Site Reliability Engineering (SRE) best practices, automated quality gates, and GitOps workflows:

* **1:** CI Pipeline & Docker Containerization with Security Scanning 🟢 *(Current Stage)*
* **2:** Local Kubernetes Orchestration (Kind) & Helm Charts packaging ⏳
* **3:** GitOps continuous delivery with ArgoCD ⏳
* **4:** Observability & Monitoring (Prometheus & Grafana dashboards) ⏳
* **5:** Infrastructure as Code (IaC) with Terraform ⏳

---

## 🛠️ Tech Stack & SRE Tools

* **Application:** FastAPI (Python 3.12), Pydantic, SQLAlchemy, PostgreSQL
* **CI/CD:** GitHub Actions
* **Containerization:** Docker (Multi-stage builds, Bookworm slim images)
* **Security:** Trivy CLI (Vulnerability Scans for filesystem & container images)
* **Quality Gates:** Black (Formatter), Ruff (Linter), Pytest & Pytest-Cov (Unit Tests & Coverage)

---

## 🟢 1st Milestone: Secure CI/CD Pipeline

The first phase of the platform is fully complete and operational. Every `git push` triggers a robust automated pipeline:

### 1. Code Quality & Testing
* **Linter & Formatter:** Code is strictly checked via `ruff` and `black` to maintain enterprise code styling.
* **Automated Tests:** Unit tests run automatically using `pytest`, generating test coverage reports.

### 2. Multi-stage Docker Builds
* The application is packaged into a highly optimized, multi-stage Docker image using a secure non-root base (`python:3.12-slim-bookworm`).
* Builds are extremely fast (under 25 seconds) and produce minimum-sized artifacts.

### 3. Proactive Security Scanning (Trivy CLI)
* **Filesystem Scan:** Scans the source code for exposed secrets and vulnerabilities before building.
* **Container Image Scan:** Scans the final Docker image layer-by-layer for high and critical vulnerabilities.

>  **SRE Implementation Note (Supply-Chain Security):** > During setup, instead of relying on third-party GitHub Actions (which can be vulnerable to supply-chain attacks or deprecation), the pipeline installs and runs the **native Trivy CLI** directly on the runner. This ensures zero Node.js deprecation warnings, maximum performance, and complete control over the security testing environment.
