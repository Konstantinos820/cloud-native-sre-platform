# Chaos Engineering Experiments

This directory contains controlled and reproducible chaos experiments for the local Kind-based SRE platform.

The objective is not simply to introduce failures, but to validate how the platform behaves during dependency degradation and outages:

```text
Fault Injection
      ↓
Failure / Degradation
      ↓
Kubernetes Detection
      ↓
Observability
      ↓
Automatic Recovery
      ↓
Post-Recovery Validation
```

These experiments are designed specifically for the local development environment and must not be executed against a production cluster.

---

## Experiments

```text
chaos/
├── postgres-latency.ps1
├── postgres-outage.ps1
└── README.md
```

Two PostgreSQL dependency scenarios are currently implemented:

1. Network latency injection
2. Complete FastAPI-to-PostgreSQL connectivity disruption

Both experiments dynamically discover the active PostgreSQL container and network namespace rather than relying on hardcoded container IDs or process IDs.

Cleanup logic is implemented so injected faults are removed even when an experiment terminates unexpectedly after fault injection.

---

# Prerequisites

The experiments assume:

- Windows PowerShell
- Docker
- kubectl
- A running Kind cluster named `kind`
- Kind control-plane container named `kind-control-plane`
- The `sre-platform` namespace
- FastAPI deployed as `sre-platform-app-fastapi`
- PostgreSQL deployed as `sre-platform-app-postgres-0`
- Linux `tc`, `iptables`, and `nsenter` available inside the Kind node

For experiments that use the host-side API endpoint, start a port-forward in a separate terminal:

```powershell
kubectl port-forward -n sre-platform service/sre-platform-app-fastapi 8000:80
```

---

# Experiment 1 — PostgreSQL Network Latency

Script:

```text
postgres-latency.ps1
```

## Hypothesis

Introducing controlled network latency between FastAPI and PostgreSQL should significantly increase database-backed request latency without necessarily causing request failures.

After removing the fault, request latency should return close to the original baseline without restarting application pods.

## Fault Injection

The experiment enters the PostgreSQL container network namespace and applies Linux `tc netem` latency to the active network interface.

Default injected delay:

```text
300 ms
```

Conceptually:

```text
FastAPI
   ↓
   ↓ +300 ms network delay
   ↓
PostgreSQL
```

The script automatically discovers:

```text
PostgreSQL Pod
      ↓
container ID
      ↓
container PID
      ↓
network namespace
      ↓
network interface
```

It also refuses to overwrite an existing `netem` rule.

---

## Automated Test Result

### Baseline

```text
Requests: 5
Success: 5/5

Average latency: 8.67 ms
Median latency:  8.57 ms
```

### During +300 ms Network Fault

```text
Requests: 5
Success: 5/5

Average latency: 910.47 ms
Median latency:  910.30 ms
```

This represents approximately a 105x increase in observed request latency while maintaining a 100% request success rate.

### Recovery

After automatic removal of the `netem` rule:

```text
Requests: 5
Success: 5/5

Average latency: 8.64 ms
Median latency:  8.53 ms
```

The recovered latency returned essentially to the original steady-state baseline.

---

## Trace Evidence

OpenTelemetry traces collected through Tempo and inspected in Grafana showed the database path becoming the dominant contributor during latency injection.

A manually inspected degraded trace showed approximately:

```text
GET /users                 ~2.17 s
├── PostgreSQL connect     ~1.55 s
└── SELECT app_db          ~609 ms
```

This provided direct trace-level evidence that the injected PostgreSQL network degradation was responsible for the increased request latency.

---

## Safety and Cleanup

The script uses PowerShell `try/finally` cleanup logic.

After the experiment:

```text
tc qdisc
```

returned to:

```text
qdisc noqueue
```

confirming that no `netem` latency rule remained active.

---

# Experiment 2 — PostgreSQL Dependency Outage

Script:

```text
postgres-outage.ps1
```

## Hypothesis

If PostgreSQL becomes unreachable from the FastAPI replicas:

- database-backed requests should fail,
- the FastAPI readiness probe should detect the dependency failure,
- Kubernetes should mark the application replicas NotReady,
- application containers should remain alive rather than being unnecessarily restarted,
- removing the fault should allow the application to recover automatically.

---

## Fault Injection

The script dynamically discovers the current FastAPI pod IP addresses and inserts PostgreSQL-side `iptables` rules that reject TCP traffic from those pods to port `5432`.

Conceptually:

```text
FastAPI Pod A ──X──► PostgreSQL :5432
FastAPI Pod B ──X──► PostgreSQL :5432
```

Example injected rules:

```text
REJECT tcp -- <fastapi-pod-ip> 0.0.0.0/0 tcp dpt:5432 reject-with tcp-reset
```

The rules are tracked individually so cleanup can remove every rule that was successfully created, including partial-failure scenarios.

---

## Automated Test Result

### Normal State

Before fault injection:

```text
FastAPI baseline request: SUCCESS
FastAPI replicas: Ready
PostgreSQL: Ready
```

### During Outage

Five requests were executed after PostgreSQL connectivity was blocked:

```text
Failed requests: 5/5
```

The first request reached FastAPI and returned:

```text
HTTP 500
```

Subsequent requests could no longer successfully reach a Ready application backend after Kubernetes readiness reacted to the dependency failure.

During the outage:

```text
FastAPI replica 1: 0/1 Running
FastAPI replica 2: 0/1 Running

Ready replicas: 0
Application restarts: 0

PostgreSQL: 1/1 Running
```

This is the expected behavior for the platform's readiness design.

The application processes remained alive, but Kubernetes stopped considering them eligible to serve traffic while their required PostgreSQL dependency was unavailable.

---

# Failure Trace Evidence

The HTTP 500 generated during the outage was captured by OpenTelemetry and inspected through Grafana / Tempo.

The trace showed:

```text
GET /users
│
├── PostgreSQL connect    ERROR
│
├── http send
└── http send
```

The failed database span contained:

```text
Kind: client
Status: error

db.system = postgresql
db.name   = app_db
db.user   = app_user

net.peer.name = sre-platform-app-postgres-headless
net.peer.port = 5432
```

The recorded exception was:

```text
sqlalchemy.exc.OperationalError
psycopg2.OperationalError
connection refused
```

No SQL `SELECT` span was present because the application failed while establishing the PostgreSQL connection before a query could be executed.

This creates a clear causal chain:

```text
iptables REJECT
      ↓
PostgreSQL connection refused
      ↓
SQLAlchemy OperationalError
      ↓
GET /users HTTP 500
      ↓
Readiness failure
      ↓
FastAPI replicas NotReady
```

---

# Automatic Recovery

The experiment removes all injected PostgreSQL `iptables` rules inside a cleanup block.

After cleanup:

```text
Ready replicas after recovery: 2
```

The recovered service was then validated from inside the Kubernetes cluster.

Result:

```text
Successful recovery requests: 5/5
```

Final application state:

```text
FastAPI replica 1: 1/1 Running
FastAPI replica 2: 1/1 Running
PostgreSQL:        1/1 Running
```

FastAPI containers required:

```text
0 restarts
```

The application therefore recovered from the dependency outage without requiring a process or pod restart.

---

## Recovery Measurement Note

The outage script intentionally validates recovery through the Kubernetes Service from inside the cluster rather than depending exclusively on `kubectl port-forward`.

During the outage all FastAPI replicas can become NotReady, which can make an existing host-side port-forward unsuitable as a recovery verification mechanism.

The recovery path therefore validates:

```text
In-Cluster Client
      ↓
Kubernetes Service
      ↓
Ready FastAPI Replica
      ↓
PostgreSQL
```

The measured recovery request durations should not be interpreted as application performance benchmarks because each validation sample includes `kubectl exec` and Python process startup overhead.

Performance measurements are handled separately by the dedicated latency and load-testing experiments.

---

# Safety and Blast Radius

These experiments intentionally modify Linux networking inside the PostgreSQL pod network namespace.

The blast radius is deliberately constrained to the local Kind development cluster.

The scripts:

- discover current runtime identifiers dynamically,
- check for stale fault rules before execution,
- avoid hardcoded pod IPs and container PIDs,
- track successfully injected rules,
- use automatic cleanup,
- verify the final network state,
- verify application recovery.

After the PostgreSQL outage experiment, the final `iptables` INPUT chain contained no injected `REJECT` rules.

After the latency experiment, the PostgreSQL interface returned to its normal `noqueue` qdisc state.

---

# Observability Pipeline

Both experiments are observable through the distributed tracing stack:

```text
FastAPI
   ↓
OpenTelemetry Instrumentation
   ↓
OTLP/gRPC
   ↓
OpenTelemetry Collector
   ↓
Tempo
   ↓
Grafana
```

Tracing includes both FastAPI server spans and SQLAlchemy database spans, allowing faults to be correlated with the affected application and PostgreSQL operations.

---

# What These Experiments Validate

Together, the two scenarios demonstrate different failure modes.

### Dependency degradation

```text
PostgreSQL becomes slow
      ↓
requests remain successful
      ↓
request latency increases dramatically
      ↓
tracing identifies database operations as the bottleneck
      ↓
fault removed
      ↓
latency returns to baseline
```

### Dependency outage

```text
PostgreSQL becomes unreachable
      ↓
database request fails
      ↓
HTTP 500 observed
      ↓
readiness detects dependency failure
      ↓
FastAPI replicas become NotReady
      ↓
fault removed
      ↓
readiness recovers
      ↓
traffic succeeds again
```

The experiments demonstrate controlled fault injection, failure detection, distributed observability, Kubernetes readiness behavior, safe cleanup, and automatic service recovery.
