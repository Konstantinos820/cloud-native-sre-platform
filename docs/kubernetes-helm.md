# Kubernetes & Helm

This document covers the Kubernetes runtime, Helm packaging, persistent PostgreSQL storage, workload health checks, network isolation, container hardening, and autoscaling ownership used by the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was to move the FastAPI + PostgreSQL workload into a reproducible Kubernetes environment while introducing the reliability and security controls expected from a cloud-native application.

---

# Overview

The local runtime is deployed on a Kind Kubernetes cluster.

The main application path is:

```text
Client
  ↓
FastAPI Service
  ↓
FastAPI Pods
  ↓
PostgreSQL Service
  ↓
PostgreSQL StatefulSet
  ↓
PersistentVolumeClaim
```

Kubernetes is responsible for workload scheduling and runtime behavior, while Helm packages the application resources into a reusable deployment unit.

```text
Helm
  ↓
Renders Kubernetes manifests
  ↓
ArgoCD
  ↓
Reconciles desired state
  ↓
Kubernetes
```

The Helm chart is stored under:

```text
charts/sre-platform-app/
```

---

# Local Kubernetes Environment

The platform runs locally using Kind.

Cluster configuration is defined in:

```text
kind-config.yaml
```

Kind provides a real Kubernetes API and controller environment while keeping the platform reproducible on a local development machine.

It is used to validate:

```text
Deployments
StatefulSets
Services
Persistent storage
Health probes
NetworkPolicies
Horizontal Pod Autoscaling
GitOps reconciliation
Monitoring
Distributed tracing
Failure experiments
```

The local Kind environment represents the executed runtime side of the project.

It is separate from the Azure Infrastructure as Code blueprint, which is validated but not provisioned.

---

# Helm Packaging

The FastAPI application and PostgreSQL resources are packaged as a Helm chart.

```text
charts/
└── sre-platform-app/
```

Helm separates reusable Kubernetes templates from environment-specific configuration.

The chart can be validated before deployment with:

```bash
helm lint charts/sre-platform-app
helm template sre-platform-app charts/sre-platform-app
```

This allows syntax, template rendering, and configuration problems to be detected before Kubernetes reconciliation.

---

# FastAPI Deployment

The application runs as a Kubernetes Deployment.

The Deployment is responsible for maintaining the desired set of FastAPI pods and supporting controlled rolling updates.

The application exposes separate operational endpoints:

```text
/health/startup
/health/live
/health/ready
```

Each endpoint has a different operational purpose.

---

# Startup, Liveness & Readiness Probes

The platform deliberately separates startup, liveness, and readiness checks.

```text
Startup
   ↓
Has the application finished starting?

Liveness
   ↓
Is the application process still alive?

Readiness
   ↓
Can this pod currently serve traffic?
```

## Startup Probe

The startup probe protects the application during initialization.

Until startup succeeds, Kubernetes does not treat failed liveness checks as evidence that the application should be restarted.

This prevents slow initialization from causing unnecessary restart loops.

---

## Liveness Probe

The liveness check determines whether the FastAPI process itself is alive.

It intentionally does not depend on PostgreSQL availability.

A temporary database failure therefore does not cause Kubernetes to restart an otherwise healthy application process.

---

## Readiness Probe

The readiness endpoint includes database availability.

If PostgreSQL cannot be reached:

```text
Database unavailable
        ↓
Readiness fails
        ↓
FastAPI pod becomes NotReady
        ↓
Pod is removed from Service endpoints
```

The process can remain alive while Kubernetes stops routing normal traffic to it.

This distinction was later validated during controlled PostgreSQL dependency-failure experiments.

---

# Rolling Updates

The FastAPI Deployment uses a rolling-update strategy configured with:

```text
maxSurge:       25%
maxUnavailable: 0
```

This means Kubernetes can create replacement pods before removing the existing ready replicas.

The intended rollout behavior is:

```text
Existing replicas serving traffic
             ↓
New replica created
             ↓
Startup succeeds
             ↓
Readiness succeeds
             ↓
New replica becomes available
             ↓
Old replica can be removed
```

Using:

```text
maxUnavailable: 0
```

helps avoid intentionally reducing the number of available application replicas during a normal rollout.

---

# PostgreSQL StatefulSet

PostgreSQL runs as a StatefulSet rather than a Deployment.

This is intentional because the database requires stable identity and persistent storage.

The StatefulSet provides:

- stable pod identity
- predictable network naming
- persistent volume association
- ordered stateful workload behavior

The database pod follows a stable identity such as:

```text
sre-platform-app-postgres-0
```

instead of being treated as an interchangeable stateless replica.

---

# Persistent Storage

PostgreSQL data is stored through a PersistentVolumeClaim.

The storage relationship is:

```text
PostgreSQL StatefulSet
         ↓
Volume Claim Template
         ↓
PersistentVolumeClaim
         ↓
PersistentVolume
```

The PVC remains independent from the lifecycle of an individual PostgreSQL pod.

If Kubernetes recreates the database pod, the persistent volume can be mounted again instead of starting with an empty database filesystem.

This allows pod replacement and storage persistence to be validated independently.

---

# Kubernetes Services

The application and database communicate through Kubernetes Services rather than pod IP addresses.

```text
FastAPI Pods
     ↓
FastAPI Service

FastAPI Pods
     ↓
PostgreSQL Service
     ↓
PostgreSQL StatefulSet
```

Pod addresses are considered ephemeral.

Kubernetes Services provide stable service discovery while pods can be recreated or replaced underneath them.

PostgreSQL is not exposed as an external public service.

---

# Network Isolation

Database ingress follows a default-deny approach.

The intended access path is:

```text
FastAPI Pods
     │
     │ TCP/5432
     ▼
PostgreSQL
```

Other workloads are not implicitly allowed to connect to PostgreSQL.

The NetworkPolicy permits database access only from the intended FastAPI application pods on:

```text
TCP/5432
```

This introduces workload-level network segmentation inside Kubernetes.

---

# Why NetworkPolicy Matters

Without a restrictive NetworkPolicy, workloads in the cluster may be able to communicate with each other more freely than necessary.

The project follows a narrower model:

```text
Default
  ↓
Deny database ingress

Explicit exception
  ↓
FastAPI application pods

Allowed destination
  ↓
PostgreSQL TCP/5432
```

This reduces unnecessary east-west connectivity between workloads.

The policy is an application-level Kubernetes control and is separate from the Azure NSG and subnet segmentation defined by Terraform.

---

# Container Hardening

The FastAPI container is also restricted at runtime.

The Kubernetes security configuration includes controls such as:

```text
Non-root execution
No privilege escalation
Dropped Linux capabilities
Read-only root filesystem
```

These controls complement the multi-stage Docker build used by the CI pipeline.

The security model therefore spans both layers:

```text
Docker image
     ↓
Minimal runtime image
Non-root user

Kubernetes runtime
     ↓
No privilege escalation
Dropped capabilities
Read-only root filesystem
Network isolation
```

The objective is to reduce unnecessary privileges rather than relying only on container isolation.

---

# Horizontal Pod Autoscaler

The FastAPI Deployment uses Kubernetes `autoscaling/v2`.

Current configuration:

```text
Minimum replicas: 2
Maximum replicas: 5
CPU target:       50%
```

The HPA receives resource metrics through:

```text
metrics-server
      ↓
HorizontalPodAutoscaler
      ↓
FastAPI Deployment
```

The HPA is responsible for changing the desired replica count in response to CPU utilization.

Detailed scaling behavior and load-test results are documented separately in:

[Load Testing & Resilience](load-testing.md)

---

# HPA & GitOps Replica Ownership

Autoscaling introduces an important controller-ownership problem.

If Helm continuously declares:

```yaml
spec:
  replicas: 2
```

while the HPA independently changes the Deployment to:

```text
3
4
5
...
```

then two controllers attempt to manage the same field.

```text
Git / ArgoCD
     ↓
replicas = 2

HPA
     ↓
replicas = dynamic
```

This creates unnecessary desired-state drift.

The project resolves this by giving replica-count ownership to the HPA whenever autoscaling is enabled.

The Helm chart therefore omits Deployment `.spec.replicas` when HPA is enabled.

ArgoCD is also configured to ignore:

```text
/spec/replicas
```

for this Deployment.

The resulting ownership boundary is:

```text
Git / Helm / ArgoCD
        ↓
Deployment configuration

HPA
        ↓
Deployment replica count
```

This allows ArgoCD to keep the application Synced and Healthy while Kubernetes dynamically scales the workload.

For the complete reconciliation behavior, see:

[GitOps with ArgoCD](gitops.md)

---

# Resource Ownership

The main runtime responsibilities are intentionally separated.

```text
Helm
  ↓
Packages Kubernetes resources

ArgoCD
  ↓
Reconciles desired Kubernetes state

Kubernetes controllers
  ↓
Maintain workload state

HPA
  ↓
Owns dynamic replica count

StatefulSet controller
  ↓
Maintains PostgreSQL identity

PersistentVolume system
  ↓
Maintains storage lifecycle
```

This avoids using one tool to manage every lifecycle in the platform.

---

# Validation

The Kubernetes and Helm layer was validated through actual execution on Kind.

Validation included:

```text
Helm linting
Helm template rendering
FastAPI Deployment
PostgreSQL StatefulSet
PersistentVolumeClaim binding
Internal Service connectivity
Startup probe behavior
Liveness probe behavior
Readiness probe behavior
Rolling updates
NetworkPolicy restrictions
Container security context
metrics-server
HorizontalPodAutoscaler
ArgoCD reconciliation
```

This is part of the executed local runtime and is not a theoretical Kubernetes architecture.

---

# Relevant Files

```text
kind-config.yaml

charts/
└── sre-platform-app/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/

argocd/

monitoring/
```

The chart contains the Kubernetes configuration for the FastAPI and PostgreSQL workload, while GitOps and monitoring resources are documented separately.

---

# Relationship to Other Layers

```text
GitHub Actions
      ↓
Validates application and container

Helm
      ↓
Packages Kubernetes resources

ArgoCD
      ↓
Reconciles them from Git

Kubernetes
      ↓
Runs FastAPI + PostgreSQL

Prometheus / Grafana
      ↓
Observe runtime behavior

HPA
      ↓
Adjusts application capacity

OpenTelemetry
      ↓
Captures request-level traces
```

This milestone provides the Kubernetes runtime foundation used by every later operational layer.

---

# Related Documentation

- [CI Pipeline & Security](ci-security.md)
- [GitOps with ArgoCD](gitops.md)
- [Observability & Alerting](observability.md)
- [Load Testing & Resilience](load-testing.md)
- [Distributed Tracing & Chaos Engineering](tracing-chaos.md)
- [Terraform & Azure](../terraform/README.md)