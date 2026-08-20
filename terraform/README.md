# Terraform — Azure Infrastructure as Code

This directory contains the Azure Infrastructure as Code layer for the **Cloud-Native SRE & GitOps Platform**.

The Terraform implementation extends the locally validated Kubernetes platform with a **production-oriented Azure infrastructure blueprint** while preserving clear responsibility boundaries between cloud infrastructure, Kubernetes packaging, and GitOps reconciliation.

> **Deployment status:** The Azure infrastructure has intentionally **not been provisioned**. The configuration has been formatted, statically validated, linted, security-scanned, tested with Terraform mock providers, and enforced through GitHub Actions CI without creating Azure resources.

---

## Architecture

Terraform owns the Azure infrastructure layer only.

```text
Terraform
    ↓
Azure Infrastructure
    │
    ├── Resource Group
    │
    ├── Virtual Network
    │   ├── AKS Subnet
    │   ├── PostgreSQL Delegated Subnet
    │   └── Private Endpoints Subnet
    │
    ├── Network Security Groups
    │
    ├── Azure Container Registry
    │   ├── Private Endpoint
    │   └── Private DNS
    │
    ├── Azure Kubernetes Service
    │   ├── Private API Server
    │   ├── System Node Pool
    │   ├── Application User Node Pool
    │   ├── Managed Identities
    │   └── Azure RBAC
    │
    ├── PostgreSQL Flexible Server
    │   ├── Delegated Subnet
    │   └── Private DNS
    │
    └── Azure Blob Storage
        ├── Private Container
        ├── Private Endpoint
        └── Private DNS

Helm
    ↓
Kubernetes Application Packaging

ArgoCD
    ↓
Continuous Kubernetes Desired-State Reconciliation
```

### Responsibility Model

```text
Terraform  → Azure cloud infrastructure
Helm       → Kubernetes application packaging
ArgoCD     → Kubernetes desired-state reconciliation
```

Terraform does not manage the application-level Kubernetes lifecycle.

This prevents cloud-resource provisioning and application deployment from becoming tightly coupled.

---

# Directory Structure

```text
terraform/
│
├── README.md
│
├── bootstrap/
│   ├── main.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── terraform.tfvars.example
│   ├── variables.tf
│   └── versions.tf
│
├── environments/
│   └── dev/
│       ├── backend.hcl.example
│       ├── locals.tf
│       ├── main.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── terraform.tfvars.example
│       ├── variables.tf
│       ├── versions.tf
│       └── tests/
│           └── dev.tftest.hcl
│
└── modules/
    ├── acr/
    │   └── tests/
    │
    ├── aks/
    │   └── tests/
    │
    ├── networking/
    │   └── tests/
    │
    ├── postgresql/
    │   └── tests/
    │
    └── storage/
        └── tests/
```

The `dev` environment composes the reusable modules into one infrastructure definition.

The `bootstrap` configuration is intentionally separate because the Terraform remote-state infrastructure must exist before the development environment can use it as a backend.

---

# Infrastructure Components

## 1. Resource Group

The development environment defines a dedicated Azure Resource Group that acts as the ownership boundary for the platform resources.

The naming convention is derived from:

```text
<project-name>-<environment>
```

For the current development configuration:

```text
sre-platform-dev
```

Common resource tags are generated centrally and propagated to supported Azure resources.

The baseline includes metadata for:

```text
project
environment
managed_by
repository
```

---

# 2. Virtual Network & Network Segmentation

The networking module defines a dedicated Azure Virtual Network.

### VNet Address Space

```text
10.20.0.0/16
```

### Subnets

```text
AKS                 10.20.0.0/23
PostgreSQL          10.20.2.0/24
Private Endpoints   10.20.3.0/24
```

This separates Kubernetes compute, the managed database, and Azure Private Link endpoints instead of placing all infrastructure inside a shared subnet.

Dedicated Network Security Groups are associated with:

```text
AKS subnet
PostgreSQL subnet
Private Endpoints subnet
```

The PostgreSQL subnet is explicitly delegated to:

```text
Microsoft.DBforPostgreSQL/flexibleServers
```

The Private Endpoints subnet enables NSG policy enforcement for Private Endpoint traffic.

---

## NSG Segmentation

The baseline goes beyond simply attaching empty NSGs.

Explicit east-west controls are defined for the PostgreSQL and Private Endpoint boundaries.

### PostgreSQL Inbound Policy

```text
ALLOW  AKS subnet         → PostgreSQL subnet TCP/5432
ALLOW  PostgreSQL subnet  → PostgreSQL subnet TCP/5432
DENY   other VNet traffic → PostgreSQL subnet
```

The first rule allows the AKS workload path to reach PostgreSQL.

The second preserves PostgreSQL communication inside the delegated subnet.

The final rule prevents unrelated VNet sources from relying on Azure's broader default `AllowVNetInBound` behavior to reach the database subnet.

### Private Endpoints Inbound Policy

```text
ALLOW  AKS subnet         → Private Endpoints subnet TCP/443
DENY   other VNet traffic → Private Endpoints subnet
```

This permits AKS nodes to access private Azure PaaS endpoints over HTTPS while restricting unrelated VNet sources.

### AKS NSG Design

The AKS NSG intentionally does **not** implement a blanket inbound deny rule.

AKS node and pod networking has platform-specific communication requirements, particularly with Azure CNI Overlay.

Workload-level Kubernetes isolation remains the responsibility of:

```text
Cilium
Kubernetes NetworkPolicy
```

This keeps Azure subnet-level security and Kubernetes workload-level security as separate control layers.

---

# 3. Azure Container Registry

The ACR module defines a private Azure Container Registry for application images.

### Baseline

```text
SKU                    Premium
Admin account          Disabled
Public network access  Disabled
Data endpoint          Enabled
Retention policy       30 days
```

Premium ACR is used to support the private connectivity model.

The registry is accessed through an Azure Private Endpoint located in the dedicated Private Endpoints subnet.

### Private DNS

```text
privatelink.azurecr.io
```

The Private DNS zone is linked to the platform VNet.

AKS does not authenticate using registry administrator credentials.

The kubelet managed identity receives:

```text
AcrPull
```

over the registry.

---

# 4. Azure Kubernetes Service

The AKS module defines a private managed Kubernetes cluster.

### Security & Platform Controls

```text
Private cluster                       Enabled
Public API FQDN                       Disabled
Local accounts                        Disabled
Azure RBAC                            Enabled
Kubernetes RBAC                       Enabled
Azure Policy                          Enabled
OIDC issuer                           Enabled
Workload Identity                     Enabled
Automatic upgrade channel             patch
Node OS upgrade channel               NodeImage
Secrets Store CSI rotation            Enabled
```

### Networking

```text
Azure CNI Overlay
Cilium dataplane
Cilium network policy
Standard Load Balancer
```

The Kubernetes pod and service networks are separate from the Azure VNet address space.

```text
Pod CIDR        10.244.0.0/16
Service CIDR    10.0.0.0/16
DNS Service IP  10.0.0.10
```

---

## AKS Node Pool Separation

The cluster uses separate system and application node pools.

### System Node Pool

```text
VM size       Standard_D4ds_v5
Autoscaling   2 → 5 nodes
Max pods      110
OS disk       Ephemeral
OS disk size  60 GB
Public IP     Disabled
```

The system pool is reserved for critical Kubernetes components.

`only_critical_addons_enabled` prevents ordinary application workloads from being scheduled there.

### Application User Node Pool

```text
VM size       Standard_D2ds_v5
Autoscaling   1 → 3 nodes
Max pods      110
OS disk       Ephemeral
OS disk size  60 GB
Public IP     Disabled
```

Application workloads therefore do not compete directly with critical Kubernetes system components.

---

# 5. AKS Managed Identity & RBAC Model

The AKS architecture uses explicit User Assigned Managed Identities rather than relying entirely on identities generated implicitly during cluster creation.

Two identities are defined:

```text
Control Plane Identity
Kubelet Identity
```

### Control Plane Identity

Receives:

```text
Network Contributor
```

on the AKS subnet.

It also receives:

```text
Managed Identity Operator
```

over the kubelet identity.

### Kubelet Identity

Receives:

```text
AcrPull
```

over the Azure Container Registry.

The resulting relationship is:

```text
Control Plane Identity
    │
    ├── Network Contributor
    │       └── AKS subnet
    │
    └── Managed Identity Operator
            └── Kubelet Identity

Kubelet Identity
    │
    └── AcrPull
            └── Azure Container Registry
```

Using explicit identities makes the Terraform dependency graph deterministic and keeps infrastructure permissions visible in code.

---

# 6. PostgreSQL Flexible Server

The PostgreSQL module defines an Azure Database for PostgreSQL Flexible Server.

### Baseline

```text
PostgreSQL version     16
SKU                    B_Standard_B1ms
Storage                32 GB
Backup retention       7 days
Geo-redundant backup   Disabled
Public network access  Disabled
```

The database is not exposed through a public endpoint.

It uses Azure VNet integration through the subnet delegated to PostgreSQL Flexible Server.

Private DNS is linked to the platform VNet.

### Authentication

The current baseline uses password authentication.

The administrator password is represented as a Terraform input that is:

```text
sensitive
ephemeral
```

and is passed through the provider's write-only administrator-password attribute.

The application database is:

```text
app_db
```

with UTF-8 encoding.

### Lifecycle Protection

Terraform lifecycle protection is applied to the stateful database resources:

```hcl
lifecycle {
  prevent_destroy = true
}
```

This provides an additional safeguard against accidental Terraform destruction.

It does not replace backups or disaster-recovery procedures.

---

## PostgreSQL Networking Model

PostgreSQL intentionally uses:

```text
Delegated Subnet
       +
Private DNS
```

rather than:

```text
Private Endpoint
```

for the Flexible Server itself.

These are different Azure networking models and are not treated as interchangeable within this architecture.

---

# 7. Azure Blob Storage

The Storage module defines private object storage for application data.

### Security Baseline

```text
Account kind                    StorageV2
Tier                            Standard
Replication                     ZRS
HTTPS only                      Enabled
Minimum TLS                     TLS 1.2
Public network access           Disabled
Public nested items             Disabled
Shared Key authorization        Disabled
Default OAuth authentication    Enabled
Local users                     Disabled
Cross-tenant replication        Disabled
Infrastructure encryption       Enabled
```

### Data Protection

```text
Blob versioning              Enabled
Blob delete retention        14 days
Container delete retention   14 days
```

The application container is private:

```text
app-data
```

### Private Connectivity

The Storage Account is accessed through an Azure Private Endpoint.

Private Blob DNS:

```text
privatelink.blob.core.windows.net
```

The Private DNS zone is linked to the VNet.

Terraform lifecycle protection is applied to persistent Storage resources.

---

## Storage Deployment Requirement

There is an important distinction between defining the Storage resources and applying them in a real Azure environment.

The Storage Account baseline uses:

```text
Shared Key authorization disabled
Public network access disabled
Private Endpoint connectivity
Microsoft Entra authentication
```

Therefore a real Terraform deployment performing Blob data-plane operations must run from an execution environment that has:

```text
1. Microsoft Entra data-plane authorization
2. Appropriate Storage RBAC
3. Network reachability to the Storage Account / Private Endpoint
```

For example, creating or managing a private Blob container cannot be assumed to work from an arbitrary public runner after the Storage Account has been completely isolated from public network access.

This repository validates the configuration statically and does not claim that this data-plane path has been live-tested against Azure.

---

# Terraform Remote State Bootstrap

The `bootstrap/` configuration defines the infrastructure required for an Azure Blob Terraform backend.

It creates:

```text
Resource Group
Storage Account
Private tfstate container
Storage Blob Data Contributor assignment
```

### Backend Storage Security

```text
HTTPS only
TLS 1.2
Shared Key disabled
OAuth authentication
Blob versioning
Soft-delete protection
Private container
```

The executing principal receives:

```text
Storage Blob Data Contributor
```

so Terraform state can be accessed using Microsoft Entra authentication instead of Storage Account keys.

---

## Why Bootstrap Uses Local State

The remote backend cannot depend on itself during initial creation.

Therefore:

```text
Bootstrap configuration
        ↓
Local Terraform state initially
        ↓
Azure backend resources created
        ↓
Development environment can use remote state
```

After a real bootstrap deployment, the resulting backend values would be used with:

```text
terraform/environments/dev/backend.hcl
```

The repository contains only:

```text
terraform/environments/dev/backend.hcl.example
```

as a template.

Example:

```hcl
storage_account_name = "REPLACE_WITH_BOOTSTRAP_OUTPUT"
container_name       = "tfstate"
key                  = "dev.terraform.tfstate"
use_azuread_auth     = true
```

The real:

```text
backend.hcl
```

is excluded from Git.

---

# Backend Connectivity Trade-off

The backend Storage Account supports configurable public network access.

This is intentional because GitHub-hosted runners execute outside the platform VNet and cannot directly reach a Private Endpoint without additional private networking.

Even when the public backend endpoint is enabled, the design still keeps:

```text
Shared Key authorization disabled
Microsoft Entra authentication required
Blob container private
```

A deployment using a self-hosted or privately connected runner could move the Terraform backend behind Azure Private Link.

---

## Future CI Authentication Requirement

The current Terraform CI pipeline intentionally performs **no Azure authentication** and does not use the remote backend.

If the project were extended into a real provisioning pipeline using GitHub Actions and Azure workload identity federation, the CI identity would need explicit authorization to the Terraform state backend.

At minimum, the deployment identity would require appropriate Blob data access such as:

```text
Storage Blob Data Contributor
```

at the intended backend scope.

This access is deliberately not granted today because the current workflow does not provision Azure infrastructure.

---

# Terraform Provider Versions

The development environment currently requires:

```text
Terraform   >= 1.15.0, < 2.0.0
AzureRM     5.1.0
```

Modules requiring generated resource-name suffixes also use the Random provider.

Provider versions are locked to improve reproducibility between local development and CI.

---

# Local Validation

The Terraform configuration can be validated without provisioning Azure infrastructure.

### Formatting

From the repository root:

```bash
terraform fmt -check -recursive terraform
```

### Initialization Without Remote Backend

Example:

```bash
terraform -chdir=terraform/environments/dev init -backend=false
```

### Validation

```bash
terraform -chdir=terraform/environments/dev validate
```

The same validation strategy is applied independently to:

```text
bootstrap
ACR module
AKS module
networking module
PostgreSQL module
storage module
development environment
```

---

# Offline Terraform Tests

Terraform native tests are stored under the corresponding module or environment `tests/` directories.

The suites use mocked providers such as:

```hcl
mock_provider "azurerm" {
  override_during = plan
}
```

and where required:

```hcl
mock_provider "random" {
  override_during = plan
}
```

Provider-computed values such as Azure resource IDs and managed-identity identifiers are replaced with deterministic test overrides.

All current test runs use:

```hcl
command = plan
```

No Azure credentials are required.

No Azure API calls are required.

No Azure resources are created.

---

# Terraform Test Coverage

Current test distribution:

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

## AKS

```text
Private cluster security baseline
System node pool controls
Application user node pool controls
Secrets Store CSI rotation
```

## Networking

```text
VNet and subnet segmentation
PostgreSQL subnet delegation
Private Endpoint subnet policies
NSG associations
PostgreSQL NSG east-west segmentation
Private Endpoint HTTPS segmentation
```

## PostgreSQL

```text
Private networking
Service configuration
Authentication baseline
Database configuration
```

## Storage

```text
Storage security controls
Blob data protection
Private connectivity
```

## ACR

```text
Registry security controls
Private DNS
Private Endpoint configuration
```

## Development Environment

```text
Root module composition
Exported infrastructure contract
```

### Current Result

```text
20 test runs passed
0 failed
```

These tests validate Terraform architecture and configuration invariants without contacting Azure.

They do **not** replace a real Azure provisioning test.

---

# TFLint

TFLint is configured at repository level through:

```text
.tflint.hcl
```

The configuration enables:

```text
Terraform recommended rules
AzureRM ruleset
```

Because `.tflint.hcl` is located at repository root, an absolute config path is used when linting recursively below `terraform/`.

### Bash

From repository root:

```bash
tflint --chdir=terraform --recursive --config "$(pwd)/.tflint.hcl"
```

### PowerShell

```powershell
$TFLINT_CONFIG = (Resolve-Path .tflint.hcl).Path
tflint --chdir=terraform --recursive --config "$TFLINT_CONFIG"
```

### Current Result

```text
0 TFLint findings
```

---

# Checkov Security Scanning

Checkov performs static security analysis across the Terraform codebase.

Current validated result:

```text
Passed checks:  84
Failed checks:  0
Skipped checks: 21
```

Skipped controls are not silently ignored.

Each intentional exception contains an inline rationale describing why that control is outside the current development baseline.

Examples include:

```text
AKS paid control-plane SLA
AKS host encryption
Customer-managed encryption keys
Azure Monitor integration
ACR geo-replication
ACR quarantine preview functionality
PostgreSQL geo-redundant backups
Terraform backend Private Endpoint
Legacy Storage Analytics controls
```

Many of these represent additional:

```text
production availability
disaster recovery
compliance
cost
deployment-specific networking
```

requirements rather than hidden failures in the current baseline.

---

# GitHub Actions — Terraform IaC CI

Terraform has a dedicated workflow:

```text
.github/workflows/terraform-ci.yml
```

Infrastructure CI is deliberately separated from the application/container workflow.

Conceptually:

```text
Terraform IaC CI
│
├── Terraform Validate & Test
│   ├── terraform fmt -check
│   ├── terraform init -backend=false
│   ├── terraform validate
│   └── terraform test
│
├── TFLint
│   └── Recursive Terraform / AzureRM linting
│
└── Checkov Security Scan
    └── Terraform security-policy analysis
```

Each job can independently fail the workflow if its corresponding quality gate fails.

---

# CI Safety Model

The current Terraform CI workflow intentionally contains no Azure authentication.

It does not perform:

```text
az login
Azure service-principal authentication
Azure OIDC authentication
terraform apply
live Azure provisioning
real Azure infrastructure deployment
```

The workflow is therefore an **offline Infrastructure as Code quality gate**, not a cloud deployment pipeline.

This distinction is intentional.

---

# Security Model

The Terraform architecture applies several security principles:

```text
Private managed services where appropriate

Private AKS control plane

No public ACR endpoint

No public application Storage endpoint

PostgreSQL private VNet integration

Separate network segments

Dedicated NSGs

Explicit managed identities

Purpose-specific Azure RBAC

Private DNS integration

Storage Shared Key authentication disabled

No plaintext Terraform deployment secrets committed to Git

Terraform lifecycle protection for stateful resources

Static security scanning

Automated IaC validation in CI
```

Sensitive deployment values are intentionally excluded from source control.

Files such as:

```text
terraform.tfvars
*.tfstate
backend.hcl
```

must remain local or be delivered through an appropriate secret/deployment mechanism.

---

# Lifecycle Protection

Stateful resources use Terraform lifecycle protection where accidental destruction would be particularly dangerous.

Example:

```hcl
lifecycle {
  prevent_destroy = true
}
```

This protection is used for persistent resources such as:

```text
PostgreSQL
Application Storage
Terraform state infrastructure where appropriate
```

`prevent_destroy` is a guardrail.

It is not a replacement for:

```text
backups
restore testing
disaster recovery
change control
```

---

# Development Baseline vs Production Hardening

This repository models a **production-oriented development baseline**.

It does not claim to represent every control that would be required for a specific organization's real production environment.

Additional production decisions could include:

```text
AKS paid control-plane SLA

Host encryption

Customer-managed encryption keys

Multi-region disaster recovery

Geo-replicated ACR

Geo-redundant PostgreSQL backups

Centralized Azure Monitor diagnostic settings

Private Terraform backend runner connectivity

Environment-specific Entra administration groups

Formal backup and restore testing

Production cost governance

Budget alerts

Policy enforcement at management-group/subscription level

Private CI/CD runner architecture
```

These controls introduce additional availability, compliance, operational, networking, or cost requirements.

They are intentionally separated from the current baseline rather than being implemented merely to increase feature count.

---

# Infrastructure Validation Model

Milestone 7 uses several independent quality layers.

```text
Terraform Source
      ↓
terraform fmt
      ↓
terraform validate
      ↓
Terraform Mock Tests
      ↓
TFLint
      ↓
Checkov
      ↓
GitHub Actions IaC CI
```

Each layer answers a different question.

| Layer | Purpose |
|---|---|
| `terraform fmt` | Is the Terraform consistently formatted? |
| `terraform validate` | Is the configuration structurally valid? |
| Terraform native tests | Are critical infrastructure invariants preserved? |
| TFLint | Does the code violate Terraform or AzureRM linting rules? |
| Checkov | Does static analysis identify security-policy weaknesses? |
| GitHub Actions | Are the quality gates automatically enforced? |

Passing all of these checks demonstrates configuration quality and consistency.

It does **not** prove that Azure has successfully provisioned every resource.

A real Azure deployment would remain a separate validation stage.

---

# Validation Boundary

The project deliberately distinguishes runtime validation from Infrastructure as Code validation.

## Milestones 1–6

The local Kind environment was actually executed and used to validate:

```text
FastAPI runtime behavior
Kubernetes scheduling
Helm packaging
ArgoCD reconciliation
Sealed Secrets
NetworkPolicies
Health probes
Prometheus metrics
Grafana dashboards
Alertmanager
Autoscaling
In-cluster load testing
Pod failure resilience
Distributed tracing
PostgreSQL fault injection
Readiness behavior
Automatic recovery
```

## Milestone 7

The Azure infrastructure layer validates:

```text
Azure resource architecture
Terraform module composition
Network segmentation
Private connectivity design
Managed identity relationships
Azure RBAC relationships
State architecture
Static Terraform correctness
Infrastructure invariants
IaC security posture
CI enforcement
```

Therefore the project represents:

```text
Executed & Validated Local Runtime
                +
Validated Azure IaC Blueprint
```

It does not present unprovisioned Azure resources as a running cloud environment.

---

# What a Real Azure Deployment Would Add

A future live deployment would introduce another validation stage:

```text
Terraform configuration
        ↓
Azure authentication
        ↓
Remote backend initialization
        ↓
terraform plan
        ↓
terraform apply
        ↓
Azure Resource Manager
        ↓
Real Azure resources
        ↓
AKS runtime validation
        ↓
ACR image pull validation
        ↓
PostgreSQL connectivity validation
        ↓
Private Endpoint / DNS validation
        ↓
End-to-end application deployment
```

That stage is intentionally outside the current portfolio validation boundary.

No chargeable Azure resources were required to complete the current milestone.

---

# Milestone 7 Outcome

The completed Infrastructure as Code milestone demonstrates:

```text
Reusable Terraform Modules
        ↓
Azure Network Segmentation
        ↓
Targeted NSG Enforcement
        ↓
Private Managed Services
        ↓
Managed Identity & RBAC
        ↓
Remote State Architecture
        ↓
Offline Infrastructure Tests
        ↓
Terraform Linting
        ↓
Security Policy Scanning
        ↓
Dedicated IaC CI Pipeline
```

Final validated baseline:

```text
Terraform test runs   20/20 passed
TFLint                0 findings
Checkov               84 passed
                      0 failed
                      21 documented skips
```

The resulting Terraform layer provides a **reproducible, security-conscious Azure infrastructure blueprint** while remaining cleanly separated from Helm-based Kubernetes packaging and ArgoCD-based GitOps reconciliation.