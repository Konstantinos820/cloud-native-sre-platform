# Cloud-Native SRE & GitOps Platform

Welcome to my enterprise-grade SRE portfolio project.

This repository is a mono-repo designed to demonstrate how a production-oriented cloud-native platform can be built around **automation, reliability, observability, security, GitOps, autoscaling, testing, distributed tracing, and infrastructure as code**.

The project is intentionally built incrementally, with every milestone introducing another layer of operational maturity.

---

## Architecture Diagram

```mermaid
graph LR
    subgraph CI [CI / CD & Registry]
        Dev[Developer / Git Push] -->|Triggers| GHA[GitHub Actions CI]
        GHA -->|Code Quality & Tests| Quality[Quality Gates]
        GHA -->|Security Scan| Trivy[Trivy]
        GHA -->|Build & Push| Registry[(Container Registry)]
    end

    subgraph Cluster [Kind Kubernetes Cluster]

        ArgoCD[ArgoCD Sync Engine] -->|Watches Git| GitRepo[GitHub Repository]

        subgraph SRE_NS [sre-platform Namespace]
            FastAPI[FastAPI Pods x2-5]
            Postgres[(PostgreSQL StatefulSet)]

            FastAPI <-->|NetworkPolicy| Postgres

            HPA[HorizontalPodAutoscaler] -->|Scales| FastAPI
            ServiceMonitor[ServiceMonitor] -->|Discovers| FastAPI
        end

        MetricsServer[metrics-server] -->|CPU / Memory Metrics| HPA

        subgraph Mon_NS [monitoring Namespace]
            Prometheus[Prometheus Operator]
            Grafana[Grafana]
            Alertmanager[Alertmanager]
            Tempo[Tempo / OTLP]

            Prometheus -->|Scrapes| ServiceMonitor
            Prometheus -->|Evaluates| Rules[Prometheus Rules]
            Rules -->|Alerts| Alertmanager

            FastAPI -->|OTLP gRPC| Tempo
        end
    end

    Alertmanager -->|Notifications| Discord[Discord #sre-alerts]

    Registry -->|Image Pull| FastAPI
````

---

# Project Roadmap

The platform is being implemented through seven progressive SRE milestones:

* **1: CI Pipeline & Docker Containerization with Security Scanning** 🟢 **Completed**
* **2: Local Kubernetes Orchestration & Helm Packaging** 🟢 **Completed**
* **3: GitOps Continuous Delivery with ArgoCD & Sealed Secrets** 🟢 **Completed**
* **4: Observability & Production-Grade Alerting** 🟢 **Completed**
* **5: Autoscaling & Load Testing** 🟢 **Completed**
* **6: Distributed Tracing & Chaos Engineering** 🟡 **In Progress**
* **7: Infrastructure as Code with Terraform** ⏳ **Planned**

---

# 🛠️ Tech Stack & SRE Tooling

### Application

* FastAPI
* Python 3.12
* Pydantic
* SQLAlchemy
* PostgreSQL

### Kubernetes & Packaging

* Kubernetes
* Kind
* Helm v3
* Kubernetes StatefulSets
* Kubernetes NetworkPolicies
* Kubernetes Probes
* Kubernetes HPA
* metrics-server

### GitOps

* ArgoCD
* Bitnami Sealed Secrets

### Observability

* Prometheus Operator
* kube-prometheus-stack
* Prometheus
* Grafana
* Alertmanager
* kube-state-metrics
* prometheus_client
* OpenTelemetry
* OTLP
* Tempo / Jaeger-compatible tracing architecture

### Testing & Load Engineering

* Pytest
* Pytest-Cov
* Locust
* Kubernetes-based load testing
* Chaos / resilience testing

### CI/CD & Security

* GitHub Actions
* Docker
* Multi-stage Docker builds
* Trivy
* Ruff
* Black

### Planned Infrastructure

* Terraform
* tflint
* Checkov

---

# 🟢 Milestone 1: Secure CI/CD Pipeline

The first phase establishes the automated software delivery and security foundation.

## 1. Code Quality & Testing

Every change is validated through automated quality gates.

* Ruff linting
* Black formatting
* Pytest
* Pytest-Cov
* Automated test execution in CI

## 2. Multi-stage Docker Builds

The application is packaged using a multi-stage Docker build based on:

`python:3.12-slim-bookworm`

The final container runs as a **non-root user** and contains only the dependencies required to run the application.

## 3. Supply-Chain Security

Trivy is executed directly inside the GitHub Actions pipeline.

The CI pipeline performs:

* Filesystem vulnerability scanning
* Secret detection
* Dependency vulnerability scanning
* Container image vulnerability scanning

The pipeline uses `--ignore-unfixed` so vulnerabilities without an available upstream fix do not unnecessarily block delivery.

> **SRE Implementation Note:** Using the native Trivy CLI instead of depending exclusively on a third-party GitHub Action gives the project greater control over the security scanning environment and makes the same scanner usable locally by developers.

---

# 🟢 Milestone 2: Local Kubernetes & Helm Packaging

The second phase moves the application from a containerized service into a Kubernetes environment.

## 1. Kind Kubernetes Cluster

A local Kubernetes cluster is provisioned using Kind.

The cluster configuration includes the networking and port mappings required for the platform.

## 2. Helm Packaging

The application infrastructure is packaged using Helm v3.

The Helm chart contains the core Kubernetes resources required to run the platform.

Configuration is separated from templates through `values.yaml`.

## 3. PostgreSQL StatefulSet

PostgreSQL runs as a Kubernetes StatefulSet.

This provides:

* Stable pod identity
* Persistent storage
* Dedicated PVC
* Stable database networking

A Headless Service provides DNS-based discovery for the PostgreSQL pod.

## 4. Network Policies

A default-deny database ingress policy is enforced.

Only the FastAPI application pods are explicitly allowed to connect to PostgreSQL on port `5432`.

## 5. Kubernetes Health Probes

The application exposes separate endpoints for different operational concerns:

### Startup

`/health/startup`

Allows the application time to initialize before other probes become relevant.

### Liveness

`/health/live`

Determines whether the application process itself is alive.

The database is intentionally not checked here.

### Readiness

`/health/ready`

Performs an active database connectivity check.

If PostgreSQL becomes unavailable, Kubernetes removes the pod from service endpoints instead of unnecessarily restarting the application.

## 6. Rolling Updates

The FastAPI Deployment uses a `RollingUpdate` strategy with:

* `maxSurge: 25%`
* `maxUnavailable: 0`

This ensures new pods become ready before existing pods are removed.

---

# 🟢 Milestone 3: GitOps Continuous Delivery

The third phase replaces manual Kubernetes deployment operations with a pull-based GitOps workflow.

## 1. ArgoCD

ArgoCD runs inside the Kubernetes cluster and continuously watches the Git repository.

The deployment flow is:

```text
Developer
   ↓
Git Push
   ↓
GitHub
   ↓
ArgoCD detects change
   ↓
Helm rendering
   ↓
Kubernetes reconciliation
```

ArgoCD is configured with:

* Automated synchronization
* `selfHeal: true`
* `prune: true`

This means Kubernetes state is continuously reconciled against Git.

### Verified

FastAPI replica scaling was performed by changing `replicaCount` in `values.yaml` and pushing the change to Git.

No manual `kubectl` or `helm upgrade` command was required.

## 2. Sealed Secrets

PostgreSQL credentials are never stored as plaintext in Git.

Bitnami Sealed Secrets is used to encrypt Kubernetes secrets client-side.

The encrypted `SealedSecret` can safely exist in the Git repository while only the controller inside the cluster can decrypt it.

---

# 🟢 Milestone 4: Observability & Production-Grade Alerting

The fourth phase introduces metrics collection, alerting, and operational visibility.

## 1. Prometheus Operator

The platform uses `kube-prometheus-stack`.

Prometheus automatically discovers application metrics through Kubernetes `ServiceMonitor` resources.

The configuration was tuned to discover custom `PrometheusRule` resources across namespaces.

## 2. Application Metrics

The FastAPI application exposes Prometheus metrics including:

* HTTP request metrics
* Request latency
* HTTP error rates
* User registration metrics

## 3. Custom SRE Alerts

Five custom alerting rules were implemented:

### FastAPIHighErrorRate

Triggers when HTTP 5xx errors exceed the defined threshold.

### FastAPIPodDown

Detects when the FastAPI Prometheus target becomes unavailable.

### FastAPIHighLatency

Detects elevated request latency using percentile-based measurements.

### PostgresDown

Uses Kubernetes state metrics to detect PostgreSQL pod readiness failures.

### FastAPIPodRestarting

Detects unexpected container restarts.

## 4. Alertmanager

Alertmanager handles alert routing and notification delivery.

Alerts are routed to a dedicated Discord channel.

The complete alert lifecycle was validated:

```text
Application / Kubernetes
        ↓
Prometheus
        ↓
PrometheusRule
        ↓
Alertmanager
        ↓
Discord
```

## 5. GitOps-Compliant Alertmanager Credentials

The Discord webhook configuration is encrypted using Sealed Secrets.

Sensitive webhook credentials are therefore not stored as plaintext in Git.

---

# 🟢 Milestone 5: Autoscaling & Load Testing

The fifth phase validates that the platform can dynamically react to workload and recover from failures.

## 1. metrics-server

The Kubernetes metrics-server provides CPU and memory metrics required by the HPA.

For the local Kind environment, the kubelet certificate configuration required:

```text
--kubelet-insecure-tls
```

This is a local Kind-specific trade-off and would not normally be required in a properly configured managed Kubernetes environment.

## 2. Horizontal Pod Autoscaler

The FastAPI Deployment uses Kubernetes `autoscaling/v2`.

Configuration:

* Minimum replicas: `2`
* Maximum replicas: `5`
* CPU target: `50%`

The HPA successfully scaled the application:

```text
2 replicas
    ↓
4 replicas
    ↓
5 replicas
```

and automatically returned to the minimum replica count after the load stopped.

## 3. Load Testing

Locust was initially executed through `kubectl port-forward`.

At high concurrency, the test produced approximately:

```text
94% failure rate
```

Investigation demonstrated that the bottleneck was the `kubectl port-forward` tunnel rather than the application itself.

The load generator was therefore moved inside the Kubernetes cluster as a Job.

This allowed Locust to communicate directly with the Kubernetes Service.

## 4. Root-Cause Investigation

The first genuine in-cluster load test revealed HTTP 500 failures.

Investigation identified several contributing factors:

* CPU limit was too restrictive.
* Database connection pool was too small.
* Database connection timeout behavior caused request failures.
* `GET /users` performed an unbounded query without pagination.

The first remediation improved the failure rate but significantly increased p95 latency.

This demonstrated that reducing the failure percentage alone does not necessarily mean the system has been fixed.

## 5. Final Load Test Result

After addressing the underlying bottlenecks:

* **29,286 requests**
* **0 failures**
* **0.00% failure rate**
* **~165 requests/second**
* **~1.2s p95 latency**
* **150 concurrent users**
* **3-minute test**

The final result demonstrated stable application behavior under sustained load.

## 6. Chaos / Resilience Test

A live FastAPI pod was forcefully terminated during a controlled load test.

Observed result:

* **20,592 requests**
* **0.09% failure rate**
* **18 failed requests**
* Failures were isolated to the short interval around pod termination.

Kubernetes automatically recreated the failed pod.

The readiness probes and remaining replicas continued serving traffic.

This validated the platform's basic Kubernetes self-healing behavior.

---

# 🟡 Milestone 6: Distributed Tracing & Chaos Engineering

This is the **current milestone**.

The goal is to extend observability from metrics into distributed request tracing and to move from a single manual pod-kill test toward reproducible chaos scenarios.

---

## 1. OpenTelemetry Application Instrumentation

OpenTelemetry tracing has now been integrated into the FastAPI application.

The application includes:

* OpenTelemetry API
* OpenTelemetry SDK
* OTLP gRPC exporter
* FastAPI instrumentation
* SQLAlchemy instrumentation

The intended request flow is:

```text
Client
  ↓
FastAPI
  ↓
SQLAlchemy
  ↓
PostgreSQL
```

with tracing information propagated through the application and database layers.

## 2. Configurable Tracing

Tracing can be enabled or disabled using environment variables.

Example:

```text
OTEL_TRACES_ENABLED=true
OTEL_SERVICE_NAME=sre-platform-api
OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.monitoring.svc.cluster.local:4317
```

Tracing is therefore controlled through deployment configuration rather than hardcoded application behavior.

## 3. Application Test Coverage

The application unit-test suite was expanded to cover:

* Database success paths
* Database failure paths
* OpenTelemetry configuration
* SQLAlchemy instrumentation
* FastAPI instrumentation
* Application startup failure
* Application startup success
* User endpoint edge cases
* Root endpoint
* Existing health endpoints
* Existing user CRUD behavior

Current result:

```text
18 tests passed
175 statements
175 statements covered
100% statement coverage
```

Coverage currently reaches:

```text
src/config.py       100%
src/database.py     100%
src/main.py         100%
src/metrics.py      100%
src/tracing.py      100%
TOTAL               100%
```

> **Important distinction:** 100% statement coverage proves the application code paths are exercised by tests. It does not yet prove that traces are successfully exported and visualized end-to-end inside the Kubernetes cluster.

## 4. Remaining Distributed Tracing Work

The remaining tracing work is cluster-level validation.

The next objective is to verify an actual trace lifecycle:

```text
HTTP Request
    ↓
FastAPI span
    ↓
SQLAlchemy span
    ↓
PostgreSQL query
    ↓
OTLP
    ↓
Tempo / Jaeger-compatible backend
    ↓
Grafana / tracing UI
```

A successful end-to-end trace must be observed from an actual request running inside Kubernetes.

## 5. Remaining Chaos Engineering Work

The manual pod-kill test from Milestone 5 already demonstrated Kubernetes self-healing.

Milestone 6 will extend this into reproducible chaos scenarios such as:

* Network latency injection
* PostgreSQL dependency failure
* Database connectivity disruption
* Service degradation
* Timeout and recovery behavior

The objective is not simply to break the system, but to verify:

```text
Failure
   ↓
Detection
   ↓
Degradation / Isolation
   ↓
Recovery
   ↓
Observable Evidence
```

---

# ⏳ Milestone 7: Infrastructure as Code

The final milestone will introduce Terraform-based infrastructure provisioning.

Planned infrastructure includes cloud-ready blueprints such as:

* VPC / networking
* Kubernetes cluster
* IAM roles
* Managed PostgreSQL
* Object storage
* Supporting cloud infrastructure

The Terraform layer will remain separated from the application Helm layer.

Planned CI quality gates include:

```text
terraform fmt
terraform validate
tflint
checkov
```

The objective is to demonstrate that the platform can move from a local Kind environment toward reproducible cloud infrastructure.

---

# 🧠 SRE Interview Notes

## Why ArgoCD instead of deploying directly from GitHub Actions?

A push-based deployment model requires the CI system to hold Kubernetes credentials.

With ArgoCD:

```text
GitHub
   ↑
   │ read
   │
ArgoCD
   │
   ↓
Kubernetes
```

The deployment controller runs inside the cluster and continuously reconciles the desired state from Git.

This reduces the need for external systems to hold direct cluster credentials and provides automatic drift correction.

---

## Why StatefulSet instead of Deployment for PostgreSQL?

PostgreSQL is stateful.

A StatefulSet provides:

* Stable identity
* Stable network naming
* Persistent storage association

A Deployment treats pods as interchangeable replicas, which is not appropriate for a single persistent database instance.

---

## Why separate liveness and readiness probes?

They answer different operational questions.

**Liveness:**

> Is the application process alive?

**Readiness:**

> Can this pod currently serve traffic?

A temporary database failure should normally remove the pod from traffic rather than cause Kubernetes to repeatedly restart it.

---

## Why use Kubernetes state metrics for PostgreSQL alerting?

For this lightweight platform, using `kube-state-metrics` avoids introducing an additional PostgreSQL exporter solely for basic pod availability monitoring.

The platform can detect PostgreSQL pod readiness directly through Kubernetes state.

---

## What did the 94% Locust failure rate teach?

The initial test was performed through `kubectl port-forward`.

The high failure rate was caused by the test transport itself rather than the application.

Moving Locust into the cluster removed the artificial bottleneck and allowed the test to measure the actual application path.

This is an important SRE principle:

> Always understand the traffic path and the test harness before interpreting load-test results.

---

## What did the first performance fix teach?

The first remediation reduced failures but increased p95 latency.

The problem was not simply a timeout value.

The investigation identified deeper resource and query issues:

* CPU constraints
* Database connection pool sizing
* Unbounded database queries

The final fix addressed the underlying bottlenecks rather than simply allowing requests to wait longer.

---

# 🏁 Repository Structure

Only the most important files and directories are shown below.

```text
cloud-native-sre-platform/
│
├── .github/workflows/
│   └── ci.yml
│
├── app/
│   ├── src/
│   │   ├── main.py
│   │   ├── database.py
│   │   ├── config.py
│   │   ├── metrics.py
│   │   └── tracing.py
│   │
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
│
├── charts/
│   └── sre-platform-app/
│
├── argocd/
│
├── monitoring/
│
├── loadtest/
│
├── locustfile.py
├── kind-config.yaml
├── pyproject.toml
├── .trivyignore
└── README.md
```

---

# 🚀 Current Status

The platform has completed the first five major SRE milestones and the application testing foundation for Milestone 6.

### Completed

* Secure CI/CD pipeline
* Multi-stage Docker build
* Trivy security scanning
* Kubernetes / Kind
* Helm
* PostgreSQL StatefulSet
* Network Policies
* Kubernetes health probes
* Rolling deployments
* ArgoCD GitOps
* Sealed Secrets
* Prometheus
* Grafana
* Alertmanager
* Discord alerting
* metrics-server
* HPA autoscaling
* In-cluster Locust load testing
* Performance root-cause investigation
* Kubernetes self-healing / pod-kill resilience test
* OpenTelemetry application instrumentation
* SQLAlchemy tracing instrumentation
* FastAPI tracing instrumentation
* **100% statement coverage**
* **18/18 unit tests passing**

### Current Work

**Milestone 6 — Distributed Tracing & Chaos Engineering**

Current focus:

1. Deploy / validate the OpenTelemetry tracing backend inside Kubernetes.
2. Verify real end-to-end traces from FastAPI → SQLAlchemy → PostgreSQL.
3. Visualize traces through the tracing UI.
4. Implement reproducible chaos scenarios.
5. Validate failure detection, isolation, recovery, and observability.

### Next

**Milestone 7 — Terraform Infrastructure as Code**

Terraform-based cloud infrastructure provisioning and CI validation.

---

# 🎯 Project Objective

The final objective is to demonstrate a complete SRE-oriented platform lifecycle:

```text
Code
 ↓
CI
 ↓
Security Scanning
 ↓
Docker
 ↓
Kubernetes
 ↓
Helm
 ↓
GitOps
 ↓
Observability
 ↓
Alerting
 ↓
Autoscaling
 ↓
Load Testing
 ↓
Chaos Engineering
 ↓
Distributed Tracing
 ↓
Infrastructure as Code
```

The emphasis throughout the project is on **measurable reliability, reproducibility, automation, failure investigation, and operational correctness**, rather than simply deploying a containerized application.
