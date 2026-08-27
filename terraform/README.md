# Terraform & Azure Infrastructure

This document covers the Azure Infrastructure as Code architecture implemented in Milestone 7 of the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was to design a reusable Azure infrastructure layer while keeping cloud provisioning separate from Kubernetes application packaging and GitOps reconciliation.

> **Important:** The Azure infrastructure defined here has intentionally **not been provisioned**. It is a validated Infrastructure as Code blueprint, not a live Azure environment.

---

# Overview

The Azure architecture is defined with Terraform and is composed from reusable modules.

```text
Terraform
   ↓
Azure Resource Group
   ↓
Networking
   ├── AKS Subnet
   ├── PostgreSQL Subnet
   └── Private Endpoint Subnet
   ↓
Private AKS
   ↓
Private ACR
   ↓
PostgreSQL Flexible Server
   ↓
Private Blob Storage
```

The infrastructure is designed around:

- private networking
- explicit identity and RBAC relationships
- controlled east-west connectivity
- private service access
- reusable Terraform modules
- static validation and native Terraform tests
- automated IaC quality gates

---

# Responsibility Boundaries

The project deliberately separates three different infrastructure and application lifecycles.

```text
Terraform  → Azure cloud infrastructure
Helm       → Kubernetes application packaging
ArgoCD     → Kubernetes desired-state reconciliation
```

Terraform does not manage the application Helm lifecycle.

ArgoCD does not provision Azure infrastructure.

Helm does not create cloud infrastructure.

This prevents unrelated lifecycle concerns from becoming tightly coupled.

---

# Terraform Structure

```text
terraform/
├── README.md
├── bootstrap/
├── environments/
│   └── dev/
│       └── tests/
└── modules/
    ├── acr/
    ├── aks/
    ├── networking/
    ├── postgresql/
    └── storage/
```

The `dev` environment composes reusable modules for:

```text
Networking
Azure Container Registry
Azure Kubernetes Service
PostgreSQL Flexible Server
Azure Blob Storage
```

This separates reusable infrastructure components from environment-level composition.

---

# Azure Network Architecture

The virtual network uses:

```text
VNet: 10.20.0.0/16
```

It is divided into three main subnets:

```text
AKS                 10.20.0.0/23
PostgreSQL          10.20.2.0/24
Private Endpoints   10.20.3.0/24
```

Dedicated Network Security Groups are associated with the subnets.

The architecture separates:

```text
Compute workloads
Database infrastructure
Private service endpoints
```

instead of placing all resources into a single flat network segment.

---

# PostgreSQL Network Controls

The PostgreSQL subnet uses explicit east-west traffic rules.

```text
ALLOW  AKS subnet         → PostgreSQL TCP/5432
ALLOW  PostgreSQL subnet  → PostgreSQL TCP/5432
DENY   other VNet traffic → PostgreSQL subnet
```

The self-subnet rule is retained because Azure Database for PostgreSQL Flexible Server requires communication within its delegated subnet.

The intended application path is:

```text
AKS
 ↓
TCP/5432
 ↓
PostgreSQL Flexible Server
```

Other VNet traffic is not implicitly allowed to reach the PostgreSQL subnet.

---

# Private Endpoint Network Controls

Private endpoints are placed in a dedicated subnet.

The primary access policy is:

```text
ALLOW  AKS subnet         → Private Endpoints TCP/443
DENY   other VNet traffic → Private Endpoints subnet
```

This limits access to services such as ACR and Blob Storage through their private endpoints.

---

# Kubernetes vs Azure Network Isolation

Azure network controls and Kubernetes NetworkPolicies operate at different layers.

```text
Azure NSGs
    ↓
Subnet and cloud-network boundaries

Kubernetes / Cilium Network Policies
    ↓
Workload-to-workload boundaries
```

The AKS subnet therefore does not rely on a blanket inbound deny rule for workload isolation.

Workload-level isolation remains the responsibility of Kubernetes networking controls.

---

# Azure Container Registry

The ACR baseline includes:

```text
Premium SKU
Admin account disabled
Public network access disabled
Dedicated data endpoint enabled
30-day untagged manifest retention
Private Endpoint
Private DNS
```

Private DNS uses:

```text
privatelink.azurecr.io
```

The registry is designed to be consumed privately from AKS.

---

# ACR Authentication

AKS does not use registry administrator credentials.

Instead:

```text
AKS Kubelet Identity
        ↓
AcrPull role
        ↓
Azure Container Registry
```

This uses Azure-managed identity and RBAC rather than static registry credentials.

The resulting model is:

```text
Identity
  +
RBAC
  +
Private network access
```

instead of:

```text
Username
  +
Password
  +
Public registry endpoint
```

---

# Private AKS

The AKS configuration includes:

```text
Private cluster
Public API FQDN disabled
Local accounts disabled
Azure RBAC
Kubernetes RBAC
Azure Policy
OIDC issuer
Workload Identity
Azure CNI Overlay
Cilium dataplane
Cilium network policy
Automatic patch upgrades
NodeImage OS upgrades
Secrets Store CSI rotation
```

The design aims to minimize unnecessary public control-plane and workload exposure.

---

# AKS Node Pools

The cluster separates system and application workloads.

## System Node Pool

```text
VM:            Standard_D4ds_v5
Autoscaling:   2 → 5
Max pods:      110
OS disk:       Ephemeral / 60 GB
Public IP:     Disabled
```

The system pool is intended for critical Kubernetes platform workloads.

## Application Node Pool

```text
VM:            Standard_D2ds_v5
Autoscaling:   1 → 3
Max pods:      110
OS disk:       Ephemeral / 60 GB
Public IP:     Disabled
```

Separating node pools allows system and application workloads to have different capacity and lifecycle characteristics.

---

# Managed Identity & RBAC

AKS uses two explicit User Assigned Managed Identities:

```text
Control Plane Identity
Kubelet Identity
```

The main RBAC relationships are:

```text
Control Plane Identity
    ├── Network Contributor → AKS subnet
    └── Managed Identity Operator → Kubelet identity

Kubelet Identity
    └── AcrPull → Azure Container Registry
```

Using explicit identities makes Terraform dependencies predictable and avoids relying on an implicitly created kubelet identity.

---

# PostgreSQL Flexible Server

The managed PostgreSQL blueprint uses:

```text
PostgreSQL version:     16
SKU:                    B_Standard_B1ms
Storage:                32 GB
Backup retention:       7 days
Public network access:  Disabled
Private VNet integration
Delegated subnet
Private DNS
```

The application database is defined as:

```text
Name:       app_db
Charset:    UTF8
Collation:  en_US.utf8
```

The database is designed to be accessible through private networking rather than a public database endpoint.

---

# PostgreSQL Credentials

The administrator password is modeled as a sensitive and ephemeral Terraform input.

It is supplied through the provider's write-only password interface.

The design avoids treating database credentials as normal Terraform output or reusable plaintext configuration.

Sensitive credentials should not be committed to the repository.

---

# Stateful Resource Protection

Lifecycle protection is applied to stateful database resources.

Stateful infrastructure has a different risk profile from stateless compute resources.

Accidental replacement of:

```text
Application pod
```

and accidental replacement of:

```text
Database infrastructure
```

do not have equivalent consequences.

The Terraform design therefore treats stateful resources more cautiously.

---

# Private Blob Storage

Application object storage uses:

```text
StorageV2
Standard tier
ZRS
HTTPS only
TLS 1.2
Public network access disabled
Shared Key authorization disabled
OAuth authentication by default
Infrastructure encryption
Blob versioning
14-day deletion retention
Private container
Private Endpoint
Private DNS
```

Private DNS uses:

```text
privatelink.blob.core.windows.net
```

The design prioritizes identity-based access and private connectivity instead of public endpoints and Shared Key authentication.

---

# Terraform Remote State Architecture

A separate bootstrap configuration defines the architecture for storing Terraform state in Azure Blob Storage.

The backend design includes:

```text
Resource Group
Storage Account
Private tfstate container
Blob versioning
Soft-delete protection
Microsoft Entra RBAC
Storage Blob Data Contributor
Shared Key disabled
```

Terraform cannot initially use infrastructure that does not yet exist.

The bootstrap configuration therefore begins with local state.

```text
Bootstrap
    ↓
Create remote-state infrastructure
    ↓
Configure environment backend
```

---

# Backend Configuration

The development environment contains:

```text
backend.hcl.example
```

while the real:

```text
backend.hcl
```

is excluded from Git.

This prevents environment-specific backend configuration from being unintentionally committed.

---

# GitHub-Hosted vs Private Runner Backend Access

There is an important connectivity trade-off for Terraform CI.

A GitHub-hosted runner cannot normally reach an Azure backend exposed only through private networking.

One possible model is:

```text
GitHub-hosted runner
        ↓
Public backend endpoint
        +
Microsoft Entra authentication
        +
Shared Key disabled
```

A private runner could instead use:

```text
Private runner
        ↓
Private Link
        ↓
Terraform backend
```

This is treated as a deployment architecture decision rather than pretending the same network model works for every runner environment.

---

# Terraform Native Tests

The Terraform codebase includes native Terraform tests.

The tests use:

```text
mock providers
deterministic overrides
planning behavior
```

They do not require:

```text
Azure credentials
Azure API calls
terraform apply
```

Current test coverage:

```text
ACR              3
AKS              3
Networking       6
PostgreSQL       4
Storage          3
Dev Composition  1
──────────────────
TOTAL           20
```

Current result:

```text
20 passed
0 failed
```

---

# What the Native Tests Validate

The tests cover infrastructure invariants such as:

- private AKS controls
- separate system and application node pools
- managed identity relationships
- network segmentation
- PostgreSQL delegation
- explicit NSG rules
- Private Endpoint policy enforcement
- ACR private connectivity
- Storage security controls
- root environment composition

These tests verify expected Terraform planning behavior.

They do **not** replace testing against a real Azure deployment.

---

# Terraform Quality Gates

The Terraform codebase is validated with:

```text
terraform fmt
terraform validate
terraform test
TFLint
Checkov
```

Current validated result:

```text
Terraform tests: 20/20 passed
TFLint:          0 findings

Checkov:
  Passed:        84
  Failed:        0
  Skipped:       21
```

The Checkov skips are documented rather than silently ignored.

---

# Checkov Skips

Examples of intentionally documented skips include controls related to:

- paid AKS SLA
- host encryption
- customer-managed encryption keys
- multi-region ACR
- PostgreSQL geo-redundant backups
- Azure Monitor integration
- private Terraform backend runner connectivity

These represent deployment-specific decisions involving:

```text
Cost
Availability
Compliance
Operational architecture
Production hardening
```

rather than hidden failures in the baseline.

---

# Dedicated Terraform CI

Terraform validation has a separate GitHub Actions workflow:

```text
.github/workflows/terraform-ci.yml
```

The pipeline contains independent jobs for:

```text
Terraform Validate & Test
TFLint
Checkov Security Scan
```

The Terraform validation flow includes:

```text
terraform fmt -check
terraform init -backend=false
terraform validate
terraform test
```

This keeps IaC validation separate from the application CI pipeline.

---

# Why the Terraform CI Does Not Deploy Azure

The workflow intentionally contains no:

```text
Azure credentials
az login
Azure OIDC authentication
terraform apply
live Azure provisioning
```

The CI pipeline therefore acts as an **Infrastructure as Code quality gate**, not an Azure deployment pipeline.

The validation boundary is:

```text
Terraform source
      ↓
Formatting
      ↓
Static validation
      ↓
Native mock tests
      ↓
TFLint
      ↓
Checkov
      ↓
GitHub Actions
```

---

# Executed Runtime vs Validated Blueprint

The project deliberately distinguishes between two kinds of evidence.

## Milestones 1–6

Executed against the real local Kind environment:

```text
Kubernetes
GitOps
Metrics
Alerting
Autoscaling
Load testing
Distributed tracing
Chaos experiments
Recovery behavior
```

## Milestone 7

Validated as Infrastructure as Code:

```text
Terraform configuration
Static validation
Native Terraform tests
TFLint
Checkov
GitHub Actions CI
```

Therefore:

```text
Executed & Validated Local Runtime
                +
Validated Azure Infrastructure Blueprint
```

The repository does not present the Azure architecture as if it were currently deployed.

---

# What This Validation Does Not Prove

The Terraform validation does not prove:

```text
Successful terraform apply against Azure
Real AKS runtime behavior
Real Azure networking connectivity
Managed PostgreSQL runtime performance
Actual Private Endpoint DNS resolution
Production failover behavior
Real cloud cost characteristics
```

Those require a provisioned Azure environment.

The repository deliberately avoids making those claims.

---

# Why This Boundary Matters

Static and mock-based Terraform validation can prove that:

```text
Configuration is syntactically valid
Modules compose correctly
Expected planning invariants hold
Linting passes
Security policies are checked
```

It cannot prove that every cloud resource will behave correctly after real provisioning.

Maintaining that distinction keeps the project evidence accurate.

---

# Relevant Files

```text
terraform/
├── README.md
├── bootstrap/
├── environments/
│   └── dev/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── backend.hcl.example
│       └── tests/
└── modules/
    ├── acr/
    ├── aks/
    ├── networking/
    ├── postgresql/
    └── storage/
```

The dedicated CI workflow is:

```text
.github/workflows/terraform-ci.yml
```

---

# Validation Summary

The Azure Infrastructure as Code layer currently demonstrates:

```text
Modular Terraform architecture
Private Azure networking
Separate AKS / PostgreSQL / Private Endpoint subnets
Explicit NSG segmentation
Private AKS
Separate system and application node pools
Azure CNI Overlay
Cilium dataplane
Workload Identity
Azure RBAC
Explicit managed identities
Private ACR
AcrPull managed-identity access
Private PostgreSQL Flexible Server
Private Blob Storage
Private DNS
Remote-state architecture
Microsoft Entra based backend authorization
20 Terraform native tests
0 Terraform test failures
0 TFLint findings
84 Checkov passed checks
0 Checkov failed checks
21 documented skips
Dedicated Infrastructure as Code CI
No terraform apply
No live Azure provisioning
```

The main result of this milestone is a reusable and security-oriented Azure Infrastructure as Code blueprint with clearly defined validation boundaries.

---

# Related Documentation

- [Root Project README](../README.md)
- [CI Pipeline & Security](../docs/ci-security.md)
- [Kubernetes & Helm](../docs/kubernetes-helm.md)
- [GitOps with ArgoCD](../docs/gitops.md)
- [Observability & Alerting](../docs/observability.md)
- [Load Testing & Resilience](../docs/load-testing.md)
- [Distributed Tracing & Chaos Engineering](../docs/tracing-chaos.md)