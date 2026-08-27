# Chaos Experiment Reference

This directory contains the reproducible chaos experiments used by the Cloud-Native SRE & GitOps Platform.

The scripts introduce controlled faults into the local Kind environment to validate application degradation, Kubernetes readiness behavior, distributed tracing, cleanup, and service recovery.

For the full design, results, and tracing analysis, see:

[Distributed Tracing & Chaos Engineering](../docs/tracing-chaos.md)

---

# Experiments

```text
chaos/
├── postgres-latency.ps1
├── postgres-outage.ps1
└── README.md
```

Two PostgreSQL dependency scenarios are implemented:

| Experiment | Fault | Purpose |
|---|---|---|
| `postgres-latency.ps1` | `tc netem delay 300ms` | Validate behavior under database network degradation |
| `postgres-outage.ps1` | PostgreSQL-side `iptables` REJECT rules | Validate complete FastAPI → PostgreSQL connectivity loss |

Both experiments include automatic cleanup logic.

---

# Important

These scripts modify Linux networking inside the PostgreSQL container network namespace of the **local Kind environment**.

They are intended for controlled local testing.

Do not run them against an environment you do not intend to disrupt.

The experiments do not provision or modify Azure infrastructure.

---

# Prerequisites

Before running either experiment:

- Docker must be running
- the Kind cluster must already exist
- the FastAPI and PostgreSQL workloads must be running
- `kubectl` must point to the local Kind cluster
- PowerShell must be available
- the FastAPI API should be reachable at `http://localhost:8000` for the default script configuration

Verify the cluster:

```powershell
kubectl config current-context
kubectl get pods -n sre-platform
```

Expected context:

```text
kind-kind
```

The application and PostgreSQL pods should be running before fault injection begins.

---

# API Access

The scripts use the FastAPI `/users` endpoint for request validation.

The default API target is:

```text
http://localhost:8000/users
```

If the application is not already exposed locally, start a port-forward from a separate PowerShell terminal.

For example:

```powershell
kubectl port-forward -n sre-platform svc/sre-platform-app-fastapi 8000:80
```

Leave that terminal open while running the experiment.

> The chaos experiments themselves target the PostgreSQL dependency path inside the Kind environment. The local API endpoint is used to initiate and measure application requests.

---

# Fault Injection Architecture

The experiments target the PostgreSQL network namespace.

```text
PowerShell Script
      ↓
kubectl / Docker
      ↓
Kind Node
      ↓
PostgreSQL container PID
      ↓
nsenter
      ↓
PostgreSQL network namespace
      ↓
tc / netem or iptables
```

Runtime values are discovered dynamically rather than relying on permanently hardcoded container IDs or process IDs.

---

# Why Direct Linux Network Faults?

The experiments use Linux networking primitives directly:

```text
tc / netem
iptables
nsenter
```

This approach was used for the local Kind environment instead of introducing an additional chaos framework.

The fault is applied to the actual PostgreSQL network path rather than simulating failures inside the FastAPI application code.

---

# Experiment 1 — PostgreSQL Network Latency

Script:

```text
postgres-latency.ps1
```

## Hypothesis

Adding PostgreSQL network latency should significantly increase the latency of database-backed requests while allowing the requests to remain successful.

After the fault is removed, request latency should return close to its original baseline without restarting FastAPI.

---

## Fault

The experiment applies:

```text
tc netem delay 300ms
```

inside the PostgreSQL network namespace.

Conceptually:

```text
FastAPI
   ↓
   ↓  artificial network delay
   ↓
PostgreSQL
```

---

## Run

From the repository root:

```powershell
.\chaos\postgres-latency.ps1
```

The script performs the experiment in stages:

```text
Pre-flight validation
        ↓
Baseline requests
        ↓
PostgreSQL network fault injection
        ↓
Degraded requests
        ↓
Fault cleanup
        ↓
Recovery requests
```

---

## Validated Result

One documented run produced:

### Baseline

```text
Requests: 5/5 successful
Average:  8.67 ms
Median:   8.57 ms
```

### During Fault

```text
Requests: 5/5 successful
Average:  910.47 ms
Median:   910.30 ms
```

This was approximately a:

```text
105x
```

increase in observed request latency.

### Recovery

```text
Requests: 5/5 successful
Average:  8.64 ms
Median:   8.53 ms
```

The application recovered without requiring a FastAPI restart.

---

# Why a 300 ms Fault Can Produce More Than 300 ms of Request Latency

The injected value is network delay, not a fixed addition to the final HTTP response time.

A database-backed request may involve several network interactions:

```text
Connection establishment
        ↓
Database protocol exchange
        ↓
SQL request
        ↓
SQL response
        ↓
Application response
```

The same degraded network path can therefore affect multiple stages of a request.

---

# Cleanup Validation

After the latency experiment, the PostgreSQL network interface should return to its normal queueing state.

The validated recovery state was:

```text
qdisc noqueue
```

The experiment includes cleanup logic so the injected `netem` rule is removed even when the experiment exits through its cleanup path.

---

# Experiment 2 — PostgreSQL Dependency Outage

Script:

```text
postgres-outage.ps1
```

## Hypothesis

If FastAPI loses connectivity to PostgreSQL:

```text
Database-backed requests should fail
        ↓
Readiness should detect dependency failure
        ↓
FastAPI replicas should become NotReady
        ↓
FastAPI processes should remain alive
        ↓
Removing the fault should restore service
```

The experiment tests dependency availability rather than terminating PostgreSQL itself.

---

# Fault

The script dynamically discovers the active FastAPI pod IP addresses and adds PostgreSQL-side rules equivalent to:

```text
REJECT FastAPI Pod A → PostgreSQL TCP/5432
REJECT FastAPI Pod B → PostgreSQL TCP/5432
```

The PostgreSQL container remains running.

The fault is:

```text
FastAPI cannot reach PostgreSQL
```

not:

```text
PostgreSQL has been stopped
```

---

# Run

From the repository root:

```powershell
.\chaos\postgres-outage.ps1
```

Default configuration includes:

```text
Namespace:          sre-platform
PostgreSQL pod:     sre-platform-app-postgres-0
FastAPI deployment: sre-platform-app-fastapi
Kind node:          kind-control-plane
API URL:            http://localhost:8000/users
Samples:            5
```

The script performs:

```text
Pre-flight validation
        ↓
Runtime discovery
        ↓
Baseline validation
        ↓
iptables fault injection
        ↓
Failure validation
        ↓
Readiness validation
        ↓
Automatic cleanup
        ↓
Recovery validation
```

---

# Validated Failure State

During the dependency outage:

```text
Requests during outage: 5/5 failed
Ready FastAPI replicas: 0
FastAPI restarts:       0
PostgreSQL:             1/1 Running
```

The first observed application failure returned:

```text
HTTP 500
```

The important distinction is:

```text
PostgreSQL process
        ↓
Still Running

Database connectivity
        ↓
Unavailable to FastAPI

FastAPI process
        ↓
Still alive

FastAPI readiness
        ↓
NotReady
```

This validates the separation between application liveness and dependency-aware readiness.

---

# Distributed Trace During Outage

The failed request was also visible through OpenTelemetry and Tempo.

The PostgreSQL connection span reported an error and included PostgreSQL connection attributes.

The captured exception included:

```text
sqlalchemy.exc.OperationalError
psycopg2.OperationalError
connection refused
```

No SQL `SELECT` span was generated for the failed request because the connection failed before the query could execute.

For the full trace analysis, see:

[Distributed Tracing & Chaos Engineering](../docs/tracing-chaos.md)

---

# Automatic Cleanup

The outage script tracks the injected rules and removes them during cleanup.

Conceptually:

```text
Injected REJECT rules
        ↓
Experiment finishes or fails
        ↓
Cleanup executes
        ↓
REJECT rules removed
```

The final PostgreSQL INPUT chain should contain no rules introduced by the experiment.

---

# Recovery Validation

After cleanup, the script waits for the FastAPI replicas to recover readiness.

The validated state was:

```text
Recovery requests: 5/5 successful
FastAPI replicas:  2 ready
FastAPI restarts:  0
PostgreSQL:        1/1
```

The script also verifies recovery by sending requests through the FastAPI Kubernetes Service from inside the cluster.

Successful completion ends with:

```text
Experiment finished
Fault cleanup completed
Service recovery verified
```

---

# Readiness vs Liveness

The dependency-outage experiment demonstrates why the application uses different health checks.

```text
Liveness
   ↓
Is FastAPI itself still alive?

Readiness
   ↓
Can FastAPI currently serve traffic correctly?
```

When PostgreSQL becomes unreachable:

```text
FastAPI process remains alive
        ↓
No restart required

Database dependency unavailable
        ↓
Readiness fails
        ↓
Pod removed from normal service
```

Restarting FastAPI would not repair a network failure between FastAPI and PostgreSQL.

---

# Experiment Safety Model

Both scripts follow the same basic lifecycle:

```text
Discover
   ↓
Validate
   ↓
Inject
   ↓
Observe
   ↓
Clean up
   ↓
Verify recovery
```

Important safeguards include:

- dynamic runtime discovery
- controlled fault scope
- automatic cleanup
- post-fault verification
- recovery checks
- no modification of persistent PostgreSQL data

These experiments target networking behavior, not the PostgreSQL persistent volume.

---

# What These Experiments Validate

Together, the two experiments cover:

```text
Dependency degradation
        +
Dependency loss
        +
Application behavior
        +
Kubernetes readiness reaction
        +
Distributed trace visibility
        +
Automatic fault cleanup
        +
Service recovery
```

They are intended as reproducible local resilience experiments, not as production disaster-recovery tests.

---

# What They Do Not Validate

The experiments do not prove:

```text
Production AKS resilience
Azure PostgreSQL failover
Multi-region recovery
Database replication behavior
Production SLO compliance
Zero-downtime failover
```

All results apply to the executed local Kind environment.

---

# Related Documentation

- [Root Project README](../README.md)
- [Distributed Tracing & Chaos Engineering](../docs/tracing-chaos.md)
- [Kubernetes & Helm](../docs/kubernetes-helm.md)
- [Observability & Alerting](../docs/observability.md)
- [Load Testing & Resilience](../docs/load-testing.md)