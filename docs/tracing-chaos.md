# Distributed Tracing & Chaos Engineering

This document covers the distributed tracing and controlled failure experiments implemented in the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was to extend observability beyond metrics and alerts into request-level tracing, then use controlled dependency failures to validate how the application behaves, how failures become visible, and how the platform recovers after the fault is removed.

---

# Overview

The tracing pipeline is:

```text
FastAPI / SQLAlchemy
        ↓
OpenTelemetry
        ↓
OTLP/gRPC
        ↓
OpenTelemetry Collector
        ↓
Tempo
        ↓
Grafana
```

The chaos experiments target the application-to-PostgreSQL dependency path:

```text
FastAPI
   ↓
PostgreSQL

   +
Controlled network fault
   ↓
Observe application behavior
   ↓
Observe traces / readiness
   ↓
Remove fault
   ↓
Validate recovery
```

Two reproducible experiments are included:

```text
PostgreSQL network latency
PostgreSQL dependency outage
```

---

# OpenTelemetry Instrumentation

The FastAPI application is instrumented with OpenTelemetry.

The instrumentation includes:

- OpenTelemetry API
- OpenTelemetry SDK
- FastAPI instrumentation
- SQLAlchemy instrumentation
- OTLP/gRPC exporter

This provides visibility into both:

```text
HTTP request processing
        +
Database interactions
```

instead of tracing only the outer HTTP request.

---

# Tracing Pipeline

Application spans are exported through OTLP/gRPC.

```text
FastAPI
   │
   ├── HTTP server spans
   │
SQLAlchemy
   │
   └── database client spans
   │
   ▼
OpenTelemetry SDK
   ↓
OTLP/gRPC
   ↓
OpenTelemetry Collector
   ↓
Tempo
   ↓
Grafana
```

The OpenTelemetry Collector acts as the telemetry pipeline between the application and Tempo.

The application does not send traces directly to Grafana.

Grafana is used to query and inspect the trace data stored in Tempo.

---

# Runtime Configuration

Tracing is enabled for the running FastAPI service.

The service identifies itself through OpenTelemetry as:

```text
sre-platform-api
```

The application exports traces to the OpenTelemetry Collector running inside Kubernetes.

Conceptually:

```text
FastAPI Pod
    ↓
otel-collector.monitoring.svc.cluster.local
    ↓
Tempo
```

Kubernetes service discovery therefore becomes part of the tracing path inside the running environment.

---

# Excluding Operational Endpoints

Health and metrics endpoints are intentionally excluded from automatic tracing.

Examples include:

```text
/health/startup
/health/live
/health/ready
/metrics
```

These endpoints are called frequently by Kubernetes and Prometheus.

Tracing every health or metrics request would generate large amounts of low-value telemetry.

The application therefore focuses trace collection on requests that provide useful application-level diagnostic information.

---

# Unit Tests vs Runtime Tracing

Tracing is enabled in the real running application but disabled during the unit-test environment.

This prevents unit tests from depending on:

```text
Kubernetes DNS
OpenTelemetry Collector
Tempo
```

The separation is:

```text
Unit tests
    ↓
Validate application code

Running Kubernetes environment
    ↓
Validate end-to-end trace export
```

This keeps test execution deterministic while preserving tracing in the environment where distributed telemetry actually matters.

---

# End-to-End Trace Validation

Tracing was validated using real traffic against the running Kubernetes application.

A database-backed request to:

```text
GET /users
```

produced an end-to-end trace containing both HTTP and database activity.

A simplified trace structure is:

```text
GET /users
│
├── connect
├── SELECT app_db
├── http send
├── http send
└── http send
```

This confirmed that instrumentation was active at both the FastAPI and SQLAlchemy layers.

---

# Database Spans

The SQLAlchemy instrumentation generates database spans for PostgreSQL operations.

Example attributes include:

```text
db.system = postgresql
db.name   = app_db
db.user   = app_user
```

The database span represents the application interaction with PostgreSQL inside the larger request trace.

Conceptually:

```text
GET /users
    ↓
FastAPI server span
    ↓
SQLAlchemy database span
    ↓
PostgreSQL
```

This makes it possible to distinguish:

```text
Time spent processing HTTP request
        vs
Time spent interacting with database
```

---

# Parent-Child Relationships

The trace data confirmed the relationship between the FastAPI server span and the SQLAlchemy client spans.

This is important because isolated spans provide less diagnostic value than a correctly connected trace.

```text
Request
  ↓
FastAPI span
  │
  ├── application work
  │
  └── SQLAlchemy span
          ↓
      PostgreSQL
```

The trace therefore exposes the path a request follows through multiple instrumentation layers.

---

# Metrics vs Traces

Prometheus and OpenTelemetry answer different operational questions.

```text
Prometheus
    ↓
Is latency increasing across the service?

Tempo
    ↓
Where inside a specific request is that latency occurring?
```

For example:

```text
Prometheus
    ↓
Request latency increased

Tempo
    ↓
Database span consumed most of the request duration
```

Metrics are useful for detecting broad behavior.

Traces are useful for investigating individual request paths and dependencies.

For metrics and alerting, see:

[Observability & Alerting](observability.md)

---

# Chaos Engineering

The project includes reproducible dependency-failure experiments under:

```text
chaos/
├── postgres-latency.ps1
├── postgres-outage.ps1
└── README.md
```

The experiments are intended to answer questions such as:

```text
What happens when PostgreSQL becomes slow?

What happens when PostgreSQL becomes unreachable?

Does readiness respond correctly?

Does the application process remain alive?

Can the fault be removed cleanly?

Does the service recover automatically?

Can the failure be observed through tracing?
```

The experiments are controlled and include cleanup logic.

---

# Fault Injection Tools

The experiments use Linux networking primitives including:

```text
tc
netem
iptables
nsenter
```

Different tools are used depending on the type of fault.

```text
tc / netem
    ↓
Network latency manipulation

iptables
    ↓
Traffic blocking

nsenter
    ↓
Enter the target network namespace
```

This makes the experiments target the actual PostgreSQL network path rather than simulating delay inside the FastAPI application code.

---

# Dynamic Runtime Discovery

The chaos scripts do not rely on permanently hardcoded runtime identifiers.

Container/runtime information is discovered dynamically before the fault is applied.

Conceptually:

```text
Locate PostgreSQL pod
        ↓
Locate PostgreSQL container
        ↓
Discover runtime PID
        ↓
Enter network namespace
        ↓
Inject fault
```

This makes the experiment more reproducible across pod or container recreation.

---

# Automatic Cleanup

Both experiments include cleanup behavior.

The intended lifecycle is:

```text
Prepare
   ↓
Inject fault
   ↓
Measure behavior
   ↓
Remove fault
   ↓
Validate recovery
```

Cleanup is important because a chaos experiment should not leave the environment permanently modified after the validation ends.

---

# PostgreSQL Network Latency Experiment

The first experiment introduces artificial network latency between the application and PostgreSQL.

The injected fault is:

```text
tc netem delay 300ms
```

This is applied to the PostgreSQL network path.

The application itself is not modified to artificially sleep or delay requests.

---

# Latency Experiment Flow

The experiment follows three stages:

```text
Baseline
   ↓
Inject 300 ms PostgreSQL network delay
   ↓
Measure degraded behavior
   ↓
Remove network fault
   ↓
Measure recovery
```

This provides both pre-fault and post-fault measurements.

---

# Baseline

Before applying the fault:

```text
Requests: 5/5 successful
Average:  8.67 ms
Median:   8.57 ms
```

This establishes normal behavior immediately before the experiment.

---

# Fault Injection

The network rule is then applied:

```text
tc netem delay 300ms
```

During the injected fault:

```text
Requests: 5/5 successful
Average:  910.47 ms
Median:   910.30 ms
```

The requests continued to succeed, but request latency increased substantially.

The observed latency increased by approximately:

```text
~105x
```

compared with the baseline measurement.

---

# Why 300 ms Can Produce More Than 300 ms Request Latency

The injected delay should not be interpreted as:

```text
Request latency = exactly +300 ms
```

A database-backed HTTP request may involve multiple network interactions.

Conceptually:

```text
HTTP request
   ↓
Acquire / establish DB connection
   ↓
Database network exchange
   ↓
SQL operation
   ↓
Response transfer
   ↓
Application response
```

Network delay can therefore affect several parts of the database interaction.

The end-to-end request latency can increase by considerably more than the nominal delay applied to a single network operation.

---

# Recovery

After the fault was removed:

```text
Requests: 5/5 successful
Average:  8.64 ms
Median:   8.53 ms
```

The application returned close to its original baseline without requiring a FastAPI restart.

The complete behavior was:

```text
Normal latency
     ↓
Network delay introduced
     ↓
Large latency increase
     ↓
Fault removed
     ↓
Latency returns to baseline
```

---

# What the Latency Experiment Validated

The experiment demonstrated:

```text
Reproducible network fault injection
        +
Successful application requests during degradation
        +
Measurable latency increase
        +
Dependency sensitivity
        +
Automatic fault cleanup
        +
Recovery without application restart
```

The experiment is therefore a resilience test rather than simply a performance benchmark.

---

# PostgreSQL Dependency Outage

The second experiment targets availability rather than latency.

FastAPI-to-PostgreSQL communication is blocked on:

```text
TCP/5432
```

The PostgreSQL process itself remains running.

The fault is specifically:

```text
Application cannot reach PostgreSQL
```

rather than:

```text
PostgreSQL process is terminated
```

---

# Outage Experiment Flow

The expected behavior is:

```text
Database traffic blocked
        ↓
Database-backed requests fail
        ↓
Readiness checks fail
        ↓
FastAPI replicas become NotReady
        ↓
Application processes remain alive
        ↓
Fault removed
        ↓
Database connectivity returns
        ↓
Readiness recovers
        ↓
Service returns automatically
```

This validates both dependency behavior and the distinction between readiness and liveness.

---

# Behavior During the Outage

Observed result:

```text
Requests:               5/5 failed
Ready FastAPI replicas: 0
FastAPI restarts:       0
PostgreSQL:             1/1 Running
```

This result is important because it shows:

```text
PostgreSQL dependency unavailable
        ↓
Application cannot currently serve DB-backed traffic

but

FastAPI process itself is still alive
```

The application pods became NotReady without entering unnecessary restart loops.

---

# Readiness vs Liveness During Dependency Failure

The experiment validates the health-probe design used by the Kubernetes workload.

```text
Liveness
    ↓
Is FastAPI itself alive?

Readiness
    ↓
Can FastAPI currently serve requests that depend on PostgreSQL?
```

During the dependency outage:

```text
FastAPI process alive
        ↓
Liveness remains valid

PostgreSQL unreachable
        ↓
Readiness fails
```

This prevents Kubernetes from repeatedly restarting an application process that cannot fix the failed external dependency by restarting itself.

---

# Trace Visibility During Failure

Tempo captured the failed PostgreSQL interaction.

The trace exposed a SQLAlchemy:

```text
OperationalError
```

associated with the failed database connection.

This demonstrates the diagnostic value of combining chaos engineering with distributed tracing.

```text
Inject dependency fault
        ↓
Application request fails
        ↓
OpenTelemetry captures failed DB interaction
        ↓
Tempo stores trace
        ↓
Failure can be inspected
```

The fault is therefore both created and observable.

---

# Recovery from the Outage

After the network block was removed:

```text
Recovery requests: 5/5 successful
FastAPI replicas:  2 ready
FastAPI restarts:  0
PostgreSQL:        1/1
```

No FastAPI restart was required.

The service recovered once PostgreSQL connectivity became available again.

The full sequence was:

```text
Healthy
   ↓
Dependency blocked
   ↓
Requests fail
   ↓
Readiness fails
   ↓
Pods become NotReady
   ↓
Processes remain alive
   ↓
Fault removed
   ↓
Connectivity restored
   ↓
Readiness succeeds
   ↓
Service recovers
```

---

# Why This Is Different from the PostgresDown Alert Test

The project contains more than one PostgreSQL-related failure validation.

They test different things.

## Observability readiness validation

```text
Controlled PostgreSQL readiness failure
        ↓
PostgresDown alert
        ↓
Alertmanager / Discord lifecycle
```

The PostgreSQL container remains running.

This primarily validates:

```text
Kubernetes state
Prometheus
PrometheusRule
Alertmanager
Notification lifecycle
```

## Dependency outage chaos experiment

```text
FastAPI → PostgreSQL TCP/5432 blocked
        ↓
Database requests fail
        ↓
FastAPI readiness fails
        ↓
Failure trace captured
        ↓
Connectivity restored
```

This primarily validates:

```text
Dependency-failure behavior
Readiness design
Tracing
Fault cleanup
Automatic application recovery
```

The experiments therefore complement each other rather than duplicate the same test.

---

# Chaos Engineering and Observability

Fault injection is significantly more useful when the resulting behavior can be observed.

The project combines:

```text
Chaos Engineering
        +
Metrics
        +
Readiness
        +
Distributed Tracing
```

For example:

```text
PostgreSQL latency injected
        ↓
Request latency increases
        ↓
Tempo exposes database span timing

PostgreSQL connectivity blocked
        ↓
Database request fails
        ↓
Readiness becomes unhealthy
        ↓
Tempo exposes SQLAlchemy OperationalError
```

This connects resilience testing directly to the observability stack.

---

# Fault Injection Is Not Recovery

The scripts remove the artificial fault, but normal platform behavior performs the actual recovery.

For example:

```text
Chaos script
    ↓
Removes network fault

Kubernetes / application
    ↓
Readiness becomes healthy again

FastAPI
    ↓
Serves successful requests again
```

The distinction is useful because:

```text
Removing the injected failure
```

and:

```text
The workload returning to a healthy operational state
```

are separate things that both need to be validated.

---

# What These Experiments Do Not Prove

These tests are controlled local resilience experiments.

They do not prove:

```text
Multi-region disaster recovery
Production AKS resilience
Managed Azure PostgreSQL failover
Zero-downtime database failover
Full network-partition tolerance
Production SLO compliance
```

The experiments validate behavior in the executed local Kind environment.

The Azure infrastructure remains an unprovisioned Infrastructure as Code blueprint.

---

# Validation Summary

The tracing and chaos milestone validated:

```text
OpenTelemetry FastAPI instrumentation
OpenTelemetry SQLAlchemy instrumentation
OTLP/gRPC trace export
OpenTelemetry Collector
Tempo trace storage
Grafana trace inspection
Real GET /users request trace
HTTP and database spans
Parent-child span relationships
PostgreSQL span attributes
Health / metrics tracing exclusion

PostgreSQL latency fault injection
tc / netem
300 ms injected network delay
Baseline measurement
Degraded measurement
Recovery measurement
5/5 successful requests during latency experiment
Automatic cleanup
Recovery without FastAPI restart

PostgreSQL dependency outage
TCP/5432 blocking
Database request failure
FastAPI readiness failure
FastAPI processes remaining alive
0 FastAPI restarts
SQLAlchemy OperationalError trace
Fault removal
5/5 successful recovery requests
2 ready FastAPI replicas after recovery
```

The key result of this milestone is not simply that tracing and chaos tools were installed.

The platform demonstrated that a controlled dependency fault could be:

```text
Injected
   ↓
Observed
   ↓
Explained
   ↓
Removed
   ↓
Recovered from
```

using the same running Kubernetes environment.

---

# Relevant Files

```text
app/
└── src/
    └── tracing.py

monitoring/
└── tracing/

chaos/
├── README.md
├── postgres-latency.ps1
└── postgres-outage.ps1
```

The application instrumentation defines trace generation, the monitoring configuration handles trace collection and storage, and the chaos scripts provide reproducible dependency-failure experiments.

---

# Related Documentation

- [CI Pipeline & Security](ci-security.md)
- [Kubernetes & Helm](kubernetes-helm.md)
- [GitOps with ArgoCD](gitops.md)
- [Observability & Alerting](observability.md)
- [Load Testing & Resilience](load-testing.md)
- [Terraform & Azure](../terraform/README.md)
- [Chaos Experiment Reference](../chaos/README.md)