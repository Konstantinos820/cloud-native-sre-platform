# Observability & Alerting

This document covers the metrics, dashboards, alerting pipeline, and end-to-end incident validation implemented in the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was to make application and platform behavior visible enough to detect operational problems, investigate them, and validate the complete alert lifecycle from metric generation to notification and recovery.

---

# Overview

The observability stack runs inside Kubernetes and is built around `kube-prometheus-stack`.

The main metrics and alerting path is:

```text
FastAPI / Kubernetes
        ↓
Prometheus
        ↓
PrometheusRule
        ↓
Alertmanager
        ↓
Discord
```

Grafana uses Prometheus as a data source for dashboards and runtime investigation.

```text
FastAPI / Kubernetes
        ↓
Prometheus
        ↓
Grafana
```

Distributed tracing is handled separately through OpenTelemetry and Tempo.

```text
FastAPI / SQLAlchemy
        ↓
OpenTelemetry Collector
        ↓
Tempo
        ↓
Grafana
```

This document focuses on the metrics and alerting side.

For tracing, see:

[Distributed Tracing & Chaos Engineering](tracing-chaos.md)

---

# Monitoring Stack

The Kubernetes monitoring environment includes:

- Prometheus Operator
- Prometheus
- Grafana
- Alertmanager
- kube-state-metrics
- node-exporter
- ServiceMonitor resources
- custom PrometheusRule resources

The stack is deployed through `kube-prometheus-stack`.

Conceptually:

```text
Kubernetes cluster
│
├── FastAPI application metrics
├── Kubernetes object state
├── Node / system metrics
│
▼
Prometheus
│
├── Grafana dashboards
└── Alert rules
        ↓
   Alertmanager
        ↓
     Discord
```

---

# Application Metrics

The FastAPI service exposes Prometheus-compatible metrics through:

```text
/metrics
```

Application metrics cover operational signals such as:

- HTTP request volume
- request latency
- HTTP error behavior
- application readiness
- user-registration activity

The project also exposes an application-specific metric for user registrations.

This provides both technical and application-level telemetry instead of monitoring only Kubernetes infrastructure.

---

# ServiceMonitor

Prometheus discovers and scrapes the FastAPI application through a Kubernetes `ServiceMonitor`.

The monitoring path is:

```text
FastAPI Pods
      ↓
Kubernetes Service
      ↓
ServiceMonitor
      ↓
Prometheus
```

The configured application metrics endpoint is:

```text
/metrics
```

with a scrape interval of:

```text
15 seconds
```

This allows Prometheus Operator to manage target discovery declaratively through Kubernetes resources rather than relying on manually maintained target configuration.

---

# Target Validation

The FastAPI scrape targets were validated directly in Prometheus.

During validation:

```text
FastAPI target 1 → UP
FastAPI target 2 → UP
```

This confirms that:

```text
Application exposes metrics
        +
Service routing works
        +
ServiceMonitor selection works
        +
Prometheus discovery works
        +
Prometheus can scrape the targets
```

A Grafana dashboard without a successfully scraped Prometheus target would not be sufficient evidence by itself, so target health was validated independently.

---

# Grafana Dashboards

Grafana is used to visualize application and Kubernetes runtime behavior.

The application dashboard focuses on signals such as:

```text
Traffic
Latency
Errors
CPU
Memory
Request volume
Application readiness
```

These signals allow the platform to answer operational questions such as:

```text
Is traffic increasing?

Are requests becoming slower?

Is the application returning more errors?

Are pods consuming excessive CPU?

Is memory pressure increasing?

Are replicas still ready to serve traffic?
```

The dashboard is intended to support investigation rather than simply provide decorative visualization.

---

# Golden Signals

The application dashboard follows the general idea of monitoring the main service-health signals.

```text
Traffic
   ↓
How much work is the service receiving?

Latency
   ↓
How long are requests taking?

Errors
   ↓
How many requests are failing?

Saturation
   ↓
How close are application resources to their limits?
```

Kubernetes and application metrics are viewed together so that service behavior can be correlated with resource behavior.

For example:

```text
Traffic increases
      ↓
CPU utilization increases
      ↓
HPA reacts
      ↓
Replica count changes
```

The autoscaling side of this behavior is documented in:

[Load Testing & Resilience](load-testing.md)

---

# Custom Prometheus Alerts

Five custom Prometheus alert rules were implemented:

```text
FastAPIHighErrorRate
FastAPIPodDown
FastAPIHighLatency
PostgresDown
FastAPIPodRestarting
```

These alerts cover different failure categories rather than monitoring a single condition.

---

## FastAPIHighErrorRate

Detects an abnormal increase in failed application requests.

Conceptually:

```text
HTTP requests
      ↓
Error ratio increases
      ↓
Threshold remains exceeded
      ↓
FastAPIHighErrorRate
```

The purpose is to detect service degradation even when the application processes themselves remain running.

---

## FastAPIPodDown

Detects loss of expected FastAPI pod availability.

This helps distinguish:

```text
Application exists
```

from:

```text
Enough application replicas are actually available
```

A Deployment object alone does not prove that its expected workload is healthy.

---

## FastAPIHighLatency

Detects sustained request latency above the configured alert condition.

Latency is treated separately from error rate because a service can remain technically successful while becoming operationally unusable due to slow responses.

```text
Requests succeed
        +
Latency becomes excessive
        ↓
Service degradation
```

---

## PostgresDown

Detects loss of PostgreSQL readiness from the Kubernetes application state.

This alert was explicitly validated through a controlled readiness-failure experiment.

The test was designed so that:

```text
PostgreSQL container
        ↓
Remained running

PostgreSQL readiness
        ↓
Failed
```

This is important because the experiment validated **readiness-based dependency monitoring**, not a full database process shutdown.

---

## FastAPIPodRestarting

Detects abnormal FastAPI restart behavior.

Repeated restarts can indicate problems such as:

```text
Application crashes
Probe failures
Resource pressure
Configuration problems
Dependency failures handled incorrectly
```

Restart monitoring provides a separate signal from simple pod availability.

---

# Alert Evaluation Pipeline

The complete alert path is:

```text
Metric
  ↓
Prometheus
  ↓
PrometheusRule expression
  ↓
Pending
  ↓
Configured duration satisfied
  ↓
Firing
  ↓
Alertmanager
  ↓
Discord
```

A notification is therefore not generated directly by Grafana.

Prometheus evaluates the alert condition, while Alertmanager handles alert delivery.

---

# End-to-End PostgresDown Validation

The `PostgresDown` rule was tested against the running Kubernetes environment instead of being left as an unverified configuration file.

The validation flow was:

```text
Healthy PostgreSQL readiness
        ↓
Controlled readiness failure introduced
        ↓
PostgreSQL container remained running
        ↓
kube_pod_status_ready reflected NotReady state
        ↓
Prometheus alert condition became true
        ↓
30-second alert duration elapsed
        ↓
PostgresDown → FIRING
        ↓
Alertmanager
        ↓
Discord critical notification
```

This validated several components at once:

```text
Kubernetes readiness state
        +
kube-state-metrics
        +
Prometheus scraping
        +
PrometheusRule evaluation
        +
Alertmanager routing
        +
Discord delivery
```

---

# Why the Database Was Not Shut Down

The validation deliberately targeted the PostgreSQL **readiness signal** rather than stopping the database container.

That distinction matters.

The observed state was:

```text
Container state:  Running
Readiness state:  NotReady
```

This allowed the test to prove that the custom alert reacted to Kubernetes readiness information rather than merely detecting that a container process disappeared.

---

# Alert Timing

The `PostgresDown` rule includes a:

```text
for: 30s
```

style evaluation period.

Conceptually:

```text
Condition becomes true
        ↓
Alert enters Pending
        ↓
Condition remains true for 30 seconds
        ↓
Alert becomes Firing
```

This avoids immediately generating an incident notification for extremely short-lived state changes.

---

# Alertmanager Notification

Once `PostgresDown` entered the firing state, Alertmanager routed the alert to Discord.

The notification confirmed:

```text
Alert:      PostgresDown
State:      FIRING
Severity:   critical
```

The important validation boundary was not simply:

```text
Prometheus rule exists
```

but:

```text
Real Kubernetes state
      ↓
Prometheus detects it
      ↓
Alert fires
      ↓
Alertmanager receives it
      ↓
External notification arrives
```

---

# Recovery Validation

The test also validated the recovery side of the incident lifecycle.

PostgreSQL readiness was restored through the normal `pg_isready` readiness probe configuration and the pod was recreated.

The recovery path was:

```text
Readiness restored
       ↓
PostgreSQL becomes Ready
       ↓
Prometheus condition clears
       ↓
PostgresDown resolves
       ↓
Alertmanager
       ↓
Discord RESOLVED notification
```

This is important because an alerting system should validate both:

```text
Detection
   +
Recovery
```

rather than only proving that a firing notification can be generated.

---

# Firing vs Resolved State

The full validated lifecycle was:

```text
Healthy
   ↓
Failure introduced
   ↓
Pending
   ↓
Firing
   ↓
FIRING notification
   ↓
Recovery
   ↓
Resolved
   ↓
RESOLVED notification
```

This shows that the alerting pipeline tracks incident state rather than sending a one-time message with no recovery feedback.

---

# GitOps State After Recovery

After the controlled validation was completed, the platform returned to its expected configuration.

The final application state was verified as:

```text
ArgoCD: Synced
Health: Healthy
```

The PostgreSQL persistent volume remained preserved.

The experiment therefore did not leave the environment in an altered or degraded state.

---

# Alertmanager Secret Management

Alertmanager requires sensitive notification configuration.

Those credentials are not stored in Git as plaintext.

The project uses Bitnami Sealed Secrets so that encrypted secret manifests can be committed to the repository while the plaintext values are only reconstructed inside the Kubernetes cluster.

The intended flow is:

```text
Sensitive notification credential
        ↓
Encrypted SealedSecret
        ↓
Git
        ↓
Sealed Secrets controller
        ↓
Kubernetes Secret
        ↓
Alertmanager
```

This keeps the observability configuration compatible with GitOps without exposing notification credentials.

---

# Metrics vs Logs vs Traces

This milestone focuses primarily on metrics and alerting.

Each observability signal answers different questions:

```text
Metrics
  ↓
What is happening at system level?

Alerts
  ↓
Does current behavior require attention?

Traces
  ↓
Where did time or failure occur inside a request?
```

For example:

```text
Prometheus
    ↓
Request latency is elevated

Tempo
    ↓
A specific SQLAlchemy database span is slow
```

Metrics identify broad system behavior while traces provide request-level causality.

The tracing implementation is documented separately in:

[Distributed Tracing & Chaos Engineering](tracing-chaos.md)

---

# Observability and Autoscaling

Prometheus monitoring and HPA autoscaling observe related runtime behavior but serve different purposes.

```text
Prometheus
    ↓
Observes and records behavior

HPA
    ↓
Changes replica count based on resource metrics
```

During load testing:

```text
Traffic increased
      ↓
CPU utilization increased
      ↓
HPA scaled application replicas
      ↓
Prometheus / Grafana exposed runtime behavior
```

The full load test and scaling results are documented in:

[Load Testing & Resilience](load-testing.md)

---

# Observability Responsibility Boundaries

The platform separates the major telemetry responsibilities.

```text
FastAPI
  ↓
Exposes application metrics

ServiceMonitor
  ↓
Defines Prometheus discovery

Prometheus
  ↓
Scrapes metrics and evaluates rules

Grafana
  ↓
Visualizes metrics

Alertmanager
  ↓
Routes alert notifications

kube-state-metrics
  ↓
Exposes Kubernetes object state

OpenTelemetry
  ↓
Produces distributed traces

Tempo
  ↓
Stores and queries traces
```

No single component is responsible for the entire observability pipeline.

---

# Validation Summary

The observability and alerting layer was validated through the running Kind environment.

Validated behavior includes:

```text
Prometheus monitoring stack running
Grafana running
Alertmanager running
ServiceMonitor discovery
FastAPI /metrics scraping
Both FastAPI Prometheus targets UP
Application and Kubernetes metrics
Grafana operational dashboards
Five custom Prometheus alert rules
PostgreSQL readiness failure detection
PostgresDown pending → firing transition
30-second alert duration
Alertmanager routing
Discord FIRING notification
Readiness restoration
Alert resolution
Discord RESOLVED notification
ArgoCD Synced / Healthy recovery
Persistent PostgreSQL storage preserved
```

The key validation was the complete incident lifecycle rather than simply confirming that the monitoring components were installed.

---

# Relevant Files

```text
monitoring/
├── ...
└── tracing/

charts/
└── sre-platform-app/

argocd/
```

Relevant configuration includes:

```text
ServiceMonitor
PrometheusRule
Alertmanager configuration
Grafana dashboards
SealedSecret resources
OpenTelemetry / Tempo configuration
```

---

# Related Documentation

- [CI Pipeline & Security](ci-security.md)
- [Kubernetes & Helm](kubernetes-helm.md)
- [GitOps with ArgoCD](gitops.md)
- [Load Testing & Resilience](load-testing.md)
- [Distributed Tracing & Chaos Engineering](tracing-chaos.md)
- [Terraform & Azure](../terraform/README.md)