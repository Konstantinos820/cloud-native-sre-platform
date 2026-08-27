# GitOps with ArgoCD

This document covers the GitOps delivery model used by the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was to replace manual Kubernetes deployment operations with a pull-based reconciliation model where Git defines the desired application state and ArgoCD continuously reconciles the cluster toward that state.

---

# Overview

The deployment flow is:

```text
Developer
    ↓
Git Change
    ↓
Git Push
    ↓
GitHub Repository
    ↓
ArgoCD detects desired-state change
    ↓
Helm rendering
    ↓
Kubernetes reconciliation
```

Git acts as the source of truth for the Kubernetes application configuration.

ArgoCD runs inside the cluster and continuously compares:

```text
Desired State
     ↓
Git repository

Live State
     ↓
Kubernetes cluster
```

When the two differ, ArgoCD reconciles the live environment toward the state declared in Git.

---

# Why Pull-Based GitOps?

A traditional push-based deployment pipeline can look like:

```text
GitHub Actions
      ↓
kubectl / Helm
      ↓
Kubernetes API
```

In that model, the external CI system needs credentials that allow it to modify the Kubernetes cluster.

This project separates those responsibilities.

```text
GitHub Actions
      ↓
Quality and security validation

Git
      ↓
Desired Kubernetes state

ArgoCD
      ↓
Cluster reconciliation
```

ArgoCD runs inside Kubernetes and pulls the desired state instead of requiring the application CI workflow to push changes directly into the cluster.

This provides:

- continuous reconciliation
- automated synchronization
- self-healing
- pruning
- reduced dependency on external Kubernetes deployment credentials

---

# ArgoCD Application Model

The application is managed through ArgoCD Application resources.

ArgoCD tracks the Helm chart stored in the repository and uses it to render the desired Kubernetes resources.

Conceptually:

```text
Git Repository
      ↓
ArgoCD Application
      ↓
Helm Chart
      ↓
Rendered Kubernetes Resources
      ↓
Cluster
```

The Helm chart remains responsible for Kubernetes packaging.

ArgoCD is responsible for reconciliation.

```text
Helm    → What Kubernetes resources should look like
ArgoCD  → Make the live cluster match that desired state
```

---

# Automated Synchronization

The ArgoCD configuration enables automated reconciliation.

```text
automated sync
selfHeal: true
prune: true
```

These options have different purposes.

## Automated Sync

When Git changes, ArgoCD can automatically synchronize the new desired state without requiring a manual synchronization action.

```text
Git updated
    ↓
ArgoCD detects difference
    ↓
Application becomes OutOfSync
    ↓
Automatic reconciliation
    ↓
Application returns to Synced
```

---

## Self-Healing

`selfHeal` allows ArgoCD to correct supported live-state drift when Kubernetes resources differ from the desired configuration stored in Git.

The intended model is:

```text
Git desired state
       ↓
       │
       ├──────────────┐
       │              │
       ▼              ▼
   Expected       Live state changed
   resource            │
                       ▼
                ArgoCD detects drift
                       │
                       ▼
                  Reconciliation
                       │
                       ▼
                Desired state restored
```

This makes Git the authoritative configuration source instead of treating manual cluster changes as permanent configuration.

---

## Pruning

`prune: true` allows ArgoCD to remove resources that were previously managed through Git but no longer exist in the desired configuration.

Without pruning:

```text
Resource removed from Git
        ↓
Old Kubernetes resource may remain
```

With pruning:

```text
Resource removed from Git
        ↓
ArgoCD detects obsolete resource
        ↓
Resource removed from cluster
```

This prevents stale managed resources from remaining indefinitely after they are removed from the repository.

---

# End-to-End GitOps Validation

The GitOps workflow was validated against the running Kind cluster.

The initial state was:

```text
Application version: 0.1.0
ArgoCD:             Synced
Health:             Healthy
```

The application version was then changed in Git:

```text
0.1.0
  ↓
0.1.1-demo
```

The change was committed and pushed to the repository.

No direct deployment command was used.

Specifically, the update was performed without:

```text
kubectl apply
helm upgrade
manual ArgoCD sync
```

ArgoCD detected the desired-state change automatically.

Observed reconciliation sequence:

```text
Synced / Healthy
       ↓
Git change detected
       ↓
OutOfSync / Healthy
       ↓
ArgoCD reconciliation
       ↓
Synced / Progressing
       ↓
Rollout completes
       ↓
Synced / Healthy
```

The live Deployment was then verified to be running:

```text
0.1.1-demo
```

This confirmed that the application change reached the cluster through the GitOps reconciliation path rather than through a manual Kubernetes deployment.

After the validation, the version was returned to:

```text
0.1.0
```

through Git, and ArgoCD automatically reconciled the runtime back to the repository state.

---

# Desired State vs Live State

ArgoCD exposes two important concepts:

```text
Sync Status
    ↓
Does the live configuration match Git?

Health Status
    ↓
Is the Kubernetes application operational?
```

These signals are related but not identical.

For example, during the GitOps validation the application could temporarily be:

```text
OutOfSync
Healthy
```

This means the existing application was still operational while the live configuration had not yet converged to the newly committed desired state.

During rollout it could then become:

```text
Synced
Progressing
```

which means the desired configuration had been applied but Kubernetes was still completing the rollout.

The final expected state is:

```text
Synced
Healthy
```

---

# HPA and ArgoCD Field Ownership

Autoscaling introduced an important GitOps ownership issue.

The original Helm configuration declared a fixed replica count:

```yaml
spec:
  replicas: 2
```

At the same time, the HorizontalPodAutoscaler was responsible for dynamically changing replicas between:

```text
2 → 5
```

This meant two controllers were attempting to manage the same field.

```text
Git / Helm / ArgoCD
        ↓
spec.replicas = 2

HPA
        ↓
spec.replicas = dynamic
```

Under load, the HPA could increase the replica count while ArgoCD continued to observe a difference between Git and the live Deployment.

This creates unnecessary reconciliation conflict.

---

# Replica Ownership Fix

The ownership model was changed so that the HPA becomes the only controller responsible for replica count while autoscaling is enabled.

The Helm chart now omits:

```text
Deployment.spec.replicas
```

when HPA is enabled.

ArgoCD is also configured to ignore:

```text
/spec/replicas
```

for the autoscaled Deployment.

The resulting ownership boundary is:

```text
Git / Helm / ArgoCD
        ↓
Deployment image
configuration
probes
resources
security context
other desired state

HPA
        ↓
Deployment replica count
```

This prevents the controllers from fighting over the same field.

The result was validated with:

```text
HPA:    min 2 / max 5
ArgoCD: Synced
Health: Healthy
```

even while the HPA dynamically changed replica count.

---

# Why Ignoring Replicas Is Not Ignoring the Deployment

ArgoCD does not stop managing the Deployment.

Only the specific field owned by the HPA is excluded from GitOps comparison.

Conceptually:

```text
Deployment
│
├── image                 → ArgoCD
├── environment           → ArgoCD
├── resources             → ArgoCD
├── probes                → ArgoCD
├── securityContext       → ArgoCD
└── replicas              → HPA
```

This is a field-ownership decision rather than disabling reconciliation.

---

# Sealed Secrets

GitOps creates a security problem if normal Kubernetes Secret manifests are committed directly to the repository.

A standard Secret can contain values encoded with Base64, but Base64 is not encryption.

The project therefore uses Bitnami Sealed Secrets.

The flow is:

```text
Sensitive value
      ↓
Sealed with cluster public key
      ↓
Encrypted SealedSecret manifest
      ↓
Committed to Git
      ↓
Sealed Secrets controller
      ↓
Decryption inside Kubernetes
      ↓
Kubernetes Secret
```

The encrypted manifest can be stored in Git without committing the plaintext secret value.

The controller running inside the intended Kubernetes cluster performs the decryption.

---

# Secret Management Boundary

The repository can contain:

```text
SealedSecret
      ↓
Encrypted data
```

but should not contain plaintext values such as:

```text
Database passwords
Discord webhook URLs
Kubernetes bearer tokens
Cloud credentials
Access tokens
Private keys
```

This allows Git to remain the desired-state source without turning the repository into a plaintext secret store.

---

# GitOps and CI Responsibilities

Application CI and GitOps intentionally perform different jobs.

```text
GitHub Actions
      ↓
Formatting
Linting
Tests
Coverage
Security scanning
Docker build validation

Git
      ↓
Desired application configuration

ArgoCD
      ↓
Kubernetes reconciliation
```

This separation means successful CI does not itself modify the Kubernetes cluster.

The application must still be represented correctly in Git before ArgoCD reconciles it.

---

# GitOps and Helm Responsibilities

Helm and ArgoCD are also not interchangeable.

```text
Helm
  ↓
Templates and packages Kubernetes resources

ArgoCD
  ↓
Continuously reconciles the rendered desired state
```

Helm answers:

```text
What should be deployed?
```

ArgoCD answers:

```text
Does the live cluster match what Git says should be deployed?
```

---

# GitOps and Terraform Responsibilities

Terraform is intentionally kept outside the Kubernetes application reconciliation lifecycle.

```text
Terraform
    ↓
Azure infrastructure

Helm
    ↓
Kubernetes application packaging

ArgoCD
    ↓
Kubernetes desired-state reconciliation
```

This keeps cloud infrastructure lifecycle and Kubernetes application lifecycle separate.

The Azure side of the project is validated as Infrastructure as Code and is not provisioned by ArgoCD.

---

# Failure and Recovery Model

The GitOps model distinguishes configuration drift from runtime failure.

For example:

```text
Wrong live configuration
        ↓
ArgoCD reconciliation

Failed application pod
        ↓
Kubernetes controller recovery

Excess CPU demand
        ↓
HPA scaling

Database unavailable
        ↓
Readiness / alerting / recovery behavior
```

ArgoCD is therefore one controller within the platform rather than the mechanism responsible for every type of recovery.

---

# Validation Summary

The GitOps layer was validated through the running local Kubernetes environment.

Validated behavior includes:

```text
ArgoCD Application reconciliation
Automated synchronization
Git as desired-state source
OutOfSync detection
Automatic rollout
Synced / Healthy recovery
No kubectl apply during GitOps deployment validation
No helm upgrade during GitOps deployment validation
No manual ArgoCD sync during validation
Sealed Secret based secret management
Self-healing configuration
Pruning configuration
HPA / ArgoCD replica ownership separation
```

The key validation was not simply that ArgoCD was installed, but that an actual Git change propagated into the running Deployment through automatic reconciliation.

---

# Relevant Files

```text
argocd/
├── application.yaml
└── ...

charts/
└── sre-platform-app/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/

.github/
└── workflows/
    └── ci.yml
```

ArgoCD Application manifests define what Git source should be reconciled, while the Helm chart defines the Kubernetes application resources.

---

# Related Documentation

- [CI Pipeline & Security](ci-security.md)
- [Kubernetes & Helm](kubernetes-helm.md)
- [Observability & Alerting](observability.md)
- [Load Testing & Resilience](load-testing.md)
- [Distributed Tracing & Chaos Engineering](tracing-chaos.md)
- [Terraform & Azure](../terraform/README.md)