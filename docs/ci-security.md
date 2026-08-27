# CI Pipeline & Security

This document covers the CI, application testing, container hardening, and security validation implemented in Milestone 1 of the Cloud-Native SRE & GitOps Platform.

The goal of this stage was to make application quality and security checks repeatable before the workload was introduced into Kubernetes.

---

## Overview

Every application change passes through an automated GitHub Actions workflow that performs:

```text
Source Change
     ↓
Formatting Check
     ↓
Linting
     ↓
Unit Tests + Coverage
     ↓
Filesystem / Secret Scan
     ↓
Docker Image Build
     ↓
Container Image Scan
```

The workflow is defined in:

```text
.github/workflows/ci.yml
```

This CI pipeline validates the application and container layer independently from the Terraform infrastructure workflow.

---

# Application Quality Gates

The Python application is checked with:

- Black
- Ruff
- Pytest
- Pytest-Cov

These tools provide separate validation signals:

```text
Black       → formatting consistency
Ruff        → static linting
Pytest      → application behavior
Pytest-Cov  → statement coverage
```

The application test suite currently contains:

```text
18 tests
175 statements
175 statements covered
100% statement coverage
```

Current result:

```text
18 passed
0 failed
100% statement coverage
```

Coverage includes:

```text
src/config.py       100%
src/database.py     100%
src/main.py         100%
src/metrics.py      100%
src/tracing.py      100%
────────────────────────
TOTAL               100%
```

The tests cover application behavior separately from the end-to-end Kubernetes and observability validation performed in later milestones.

---

# Test Environment Isolation

Distributed tracing is enabled in the running application, but unit tests should not depend on the availability of the Kubernetes tracing stack.

The test environment therefore disables OpenTelemetry trace exporting.

This keeps unit tests isolated from infrastructure dependencies such as:

```text
OpenTelemetry Collector
Tempo
Kubernetes service discovery
```

The test suite can therefore run locally or inside GitHub Actions without requiring the monitoring stack to exist.

This separation is intentional:

```text
Unit Tests
    ↓
Validate application code

Running Kubernetes Environment
    ↓
Validate real OpenTelemetry traces
```

Application test coverage and end-to-end tracing are treated as different validation signals.

---

# Dependency Management

Runtime dependencies are defined in:

```text
app/requirements.txt
```

Development and test dependencies are defined in:

```text
app/requirements-dev.txt
```

Installing the development requirements also installs the application runtime dependencies:

```bash
pip install -r app/requirements-dev.txt
```

The development dependency set includes tooling required for:

```text
Testing
Coverage
Formatting
Linting
Test environment configuration
```

---

# Docker Containerization

The FastAPI application uses a multi-stage Docker build based on:

```text
python:3.12-slim-bookworm
```

The build separates dependency/build concerns from the final runtime image.

The final container is designed to minimize unnecessary runtime privileges and files.

Key controls include:

- multi-stage build
- non-root execution
- runtime-only dependencies
- no privilege escalation
- dropped Linux capabilities
- read-only root filesystem at the Kubernetes layer

This reduces both the container attack surface and the impact of a potential application compromise.

---

# Security Scanning

Trivy is used at two different stages.

## Repository / Filesystem Scan

The repository scan checks the source tree for issues such as:

- exposed secrets
- vulnerable supported dependencies
- filesystem-level security findings

It runs before the container image is accepted by CI.

Secret scanning is especially important because the project also contains GitOps and infrastructure configuration.

Sensitive values should never be stored in Git as plaintext.

Kubernetes secrets used by the platform are handled later through Bitnami Sealed Secrets.

---

## Container Image Scan

After the Docker image is built, Trivy scans the resulting image.

The scan evaluates supported operating-system and application package targets inside the container image.

The purpose of this step is to prevent an image with known security issues from passing through CI unnoticed.

The workflow therefore validates both:

```text
Repository contents
        +
Built container image
```

instead of relying on only one type of scan.

---

# CI Workflow Separation

The repository contains two independent GitHub Actions workflows:

```text
.github/workflows/
├── ci.yml
└── terraform-ci.yml
```

## `ci.yml`

Responsible for the application and container layer:

```text
Formatting
Linting
Application tests
Coverage
Filesystem security scanning
Docker build
Container image scanning
```

## `terraform-ci.yml`

Responsible for Infrastructure as Code validation:

```text
Terraform formatting
Terraform validation
Terraform native tests
TFLint
Checkov
```

Keeping these workflows separate prevents application delivery checks and cloud infrastructure validation from becoming unnecessarily coupled.

---

# Why CI Does Not Deploy Kubernetes

The application CI workflow validates the application and produces a validated container build, but it does not directly deploy Kubernetes resources.

Kubernetes desired state is managed through Git and reconciled by ArgoCD.

The responsibility boundary is:

```text
GitHub Actions
      ↓
Application quality and security validation

Git
      ↓
Desired Kubernetes state

ArgoCD
      ↓
Cluster reconciliation
```

This avoids giving the application CI workflow responsibility for direct Kubernetes deployment.

For the complete GitOps design, see:

[GitOps with ArgoCD](gitops.md)

---

# Validation Results

Current application validation:

| Check | Result |
|---|---|
| Unit tests | **18/18 passing** |
| Statement coverage | **100%** |
| Covered statements | **175/175** |
| Formatting | **Black** |
| Linting | **Ruff** |
| Repository security scanning | **Trivy** |
| Container image scanning | **Trivy** |

The CI pipeline provides a repeatable quality and security baseline before the application reaches the Kubernetes layer.

---

# Relevant Files

```text
.github/workflows/ci.yml

app/
├── Dockerfile
├── requirements.txt
├── requirements-dev.txt
├── pytest.ini
├── src/
│   ├── config.py
│   ├── database.py
│   ├── main.py
│   ├── metrics.py
│   └── tracing.py
└── tests/
```

---

# Related Documentation

- [Kubernetes & Helm](kubernetes-helm.md)
- [GitOps with ArgoCD](gitops.md)
- [Observability & Alerting](observability.md)
- [Load Testing & Resilience](load-testing.md)
- [Distributed Tracing & Chaos Engineering](tracing-chaos.md)
- [Terraform & Azure](../terraform/README.md)