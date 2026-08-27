# Load Testing & Resilience

This document covers the autoscaling, load-testing methodology, performance investigation, and pod-failure resilience validation implemented in the Cloud-Native SRE & GitOps Platform.

The goal of this milestone was not only to generate traffic, but to observe how the application behaved under sustained load, identify real bottlenecks, validate Horizontal Pod Autoscaler behavior, and test how Kubernetes handled the loss of an application pod.

---

# Overview

The main validation flow was:

```text
Locust
  ↓
FastAPI Service
  ↓
FastAPI Pods
  ↓
PostgreSQL
```

The application runs behind a Kubernetes Service and uses a HorizontalPodAutoscaler based on CPU utilization.

```text
metrics-server
      ↓
HPA
      ↓
FastAPI Deployment
      ↓
Replica count
```

The load test was executed inside the Kubernetes cluster so traffic could reach the application through the same Service path used by other cluster workloads.

---

# Horizontal Pod Autoscaler

The FastAPI Deployment uses Kubernetes `autoscaling/v2`.

Current configuration:

```text
Minimum replicas: 2
Maximum replicas: 5
CPU target:       50%
```

The HPA uses CPU utilization provided through `metrics-server`.

```text
FastAPI Pods
      ↓
Resource usage
      ↓
metrics-server
      ↓
HorizontalPodAutoscaler
      ↓
Deployment replica count
```

The 50% value is a utilization target rather than a fixed CPU threshold.

---

# Scaling Behavior

Before the load test, the application was running at its minimum replica count:

```text
Replicas: 2
CPU target: 50%
```

Under sustained load, CPU utilization increased above the configured target.

The HPA reacted by scaling the application:

```text
2 replicas
    ↓
4 replicas
    ↓
5 replicas
```

The maximum configured replica count was therefore reached during the test.

After traffic stopped and resource demand returned to normal, Kubernetes automatically scaled the workload back down:

```text
5
↓
2 replicas
```

No manual `kubectl scale` operation was required.

---

# Why Autoscaling Was Tested Under Real Load

Simply defining an HPA resource does not prove that autoscaling works.

The validation needed to demonstrate the full control loop:

```text
Traffic increases
      ↓
CPU utilization increases
      ↓
metrics-server exposes resource metrics
      ↓
HPA observes target deviation
      ↓
Desired replicas increase
      ↓
Deployment creates additional pods
      ↓
Traffic stops
      ↓
CPU utilization falls
      ↓
HPA scales back down
```

This verifies actual runtime behavior rather than only configuration syntax.

---

# Initial Load-Test Methodology

The first high-concurrency test sent traffic through:

```text
Locust
  ↓
kubectl port-forward
  ↓
Kubernetes Service
  ↓
FastAPI
```

That test produced an apparent failure rate of approximately:

```text
94%
```

At first, this looked like severe application instability.

Further investigation showed that the main bottleneck was the `kubectl port-forward` transport rather than the application itself. :contentReference[oaicite:1]{index=1}

---

# Why `kubectl port-forward` Was a Problem

`kubectl port-forward` is useful for development and debugging, but it is not intended to act as a high-throughput load-generation path.

The original test was therefore measuring more than just the application:

```text
Locust
  ↓
Local machine
  ↓
kubectl port-forward
  ↓
Kubernetes API transport
  ↓
Service
  ↓
Application
```

This introduced an artificial transport bottleneck.

The test path was changed so the load generator ran inside Kubernetes.

---

# In-Cluster Locust

Locust was moved into the Kubernetes cluster.

The new test path became:

```text
Locust Pod
    ↓
Kubernetes Service
    ↓
FastAPI Pods
    ↓
PostgreSQL
```

This removed the local port-forward transport from the measurement path.

The test could then focus on the real application-to-Service behavior.

---

# Real Application Bottlenecks

Once Locust was running inside the cluster, the test exposed genuine application bottlenecks.

The main issues identified were:

- restrictive CPU limits
- insufficient database connection-pool capacity
- connection timeout behavior
- an unbounded `GET /users` query

These were application and runtime issues rather than artifacts introduced by the load-generation transport. :contentReference[oaicite:2]{index=2}

---

# CPU Constraints

Under sustained concurrency, restrictive CPU limits reduced the amount of compute available to the FastAPI application.

The relationship was:

```text
Load increases
      ↓
Application CPU demand increases
      ↓
CPU constraints become visible
      ↓
Request latency / throughput affected
```

The HPA could add replicas, but each pod still needed enough CPU capacity to process requests effectively.

Autoscaling therefore does not replace correct per-pod resource sizing.

---

# Database Connection Pool

The application also exposed database connection-pool limitations under concurrency.

Conceptually:

```text
More concurrent requests
        ↓
More database operations
        ↓
Connection demand increases
        ↓
Pool capacity becomes constrained
```

This demonstrated that scaling the application tier can increase pressure on downstream dependencies.

Adding application replicas alone does not guarantee higher throughput if the database connection layer becomes the next bottleneck.

---

# Connection Timeout Behavior

Database connection pressure also exposed timeout-related behavior.

This was useful because it showed the importance of treating downstream dependency limits as part of performance testing.

```text
Application concurrency
        ↓
Database connection demand
        ↓
Pool / timeout behavior
        ↓
Request performance
```

Load testing therefore covered more than CPU scaling.

---

# Unbounded `GET /users` Query

The database-backed:

```text
GET /users
```

endpoint initially returned an unbounded result set.

Under sustained load, this increased database and application work unnecessarily.

The test showed how seemingly simple application-level behavior can become a performance issue when concurrency increases.

This is one example of why load testing is useful for finding problems that are not obvious during normal functional testing.

---

# Final Sustained Load Test

After addressing the identified bottlenecks, the final in-cluster test used:

```text
Concurrent users: 150
Duration:         3 minutes
```

Final result:

```text
Requests:          29,286
Failures:          0
Failure rate:      0.00%
Throughput:        ~165 req/s
p95 latency:       ~1.2 s
Concurrent users:  150
Duration:          3 minutes
```

The final run remained stable under sustained load. :contentReference[oaicite:3]{index=3}

---

# Interpreting the Result

The important result is not simply:

```text
29,286 requests
```

but the combination of:

```text
Sustained concurrency
        +
0 application failures
        +
HPA scaling
        +
Measured latency
        +
Measured throughput
```

This provides a more useful operational picture than a single performance number.

The test should not be interpreted as a universal benchmark.

The results apply to the specific local Kind environment, application configuration, database configuration, workload pattern, and machine on which the experiment was executed.

---

# Throughput

The final sustained run reached approximately:

```text
165 requests / second
```

Throughput represents the number of completed requests per second during the workload.

It should be interpreted together with latency and error rate.

Higher throughput alone is not useful if:

```text
Errors increase
or
Latency becomes unacceptable
```

---

# Latency

The final test recorded approximately:

```text
p95 latency: ~1.2 seconds
```

p95 means approximately 95% of measured requests completed at or below that latency.

This is more informative than average latency alone because averages can hide slower requests.

---

# Failure Rate

The final sustained run completed with:

```text
0 failures
0.00% failure rate
```

This result was achieved after the earlier bottlenecks were investigated and addressed.

It should therefore be viewed as the result of the troubleshooting process rather than the initial behavior of the application.

---

# HPA During Load

While Locust generated sustained traffic:

```text
Traffic
  ↓
CPU utilization rises
  ↓
HPA reacts
  ↓
2 replicas
  ↓
4 replicas
  ↓
5 replicas
```

The HPA reached the configured maximum of five FastAPI replicas.

After the workload ended:

```text
Traffic stops
  ↓
CPU utilization falls
  ↓
HPA stabilization period
  ↓
Replica count decreases
  ↓
2 replicas
```

This demonstrated both scale-up and scale-down behavior.

---

# HPA and ArgoCD

The replica count is dynamically owned by the HPA when autoscaling is enabled.

The Helm chart does not declare `.spec.replicas` in that mode, and ArgoCD ignores `/spec/replicas`.

This prevents:

```text
ArgoCD
  ↓
Trying to restore replicas = 2

while

HPA
  ↓
Trying to scale replicas dynamically
```

The ownership model is:

```text
ArgoCD
  ↓
Application desired state

HPA
  ↓
Dynamic replica count
```

For the full controller-ownership discussion, see:

[GitOps with ArgoCD](gitops.md)

---

# Pod-Kill Resilience Test

Autoscaling validates capacity management, but it does not directly prove how the service behaves when a running application instance disappears.

A separate resilience experiment was therefore performed.

During sustained traffic, one FastAPI pod was forcefully terminated.

```text
Sustained traffic
      ↓
FastAPI replicas serving requests
      ↓
One FastAPI pod terminated
      ↓
Remaining replicas continue serving
      ↓
Kubernetes recreates missing pod
```

---

# Pod-Kill Result

Observed result:

```text
Requests:      20,592
Failed:        18
Failure rate:  0.09%
```

The failures occurred during the short window surrounding the pod termination. :contentReference[oaicite:4]{index=4}

Kubernetes recreated the failed pod automatically while the remaining application replicas continued serving traffic.

---

# Why Some Requests Failed

Kubernetes self-healing does not guarantee that every in-flight request survives the immediate loss of a process.

A pod can disappear while it is handling active connections or requests.

The observed behavior was therefore:

```text
Pod terminated
      ↓
Small number of requests affected
      ↓
Remaining replicas continue serving
      ↓
Replacement pod created
      ↓
Desired capacity restored
```

The 0.09% failure rate represents the brief disruption around the failure event rather than a prolonged service outage.

---

# What the Pod-Kill Test Validated

The experiment demonstrated:

```text
Multiple application replicas
        +
Service-level traffic distribution
        +
Kubernetes Deployment reconciliation
        +
Automatic pod replacement
        +
Continued service during partial replica loss
```

It also showed that high availability is not the same as perfect zero-request-loss behavior during abrupt process termination.

---

# Resilience vs Autoscaling

These tests validate different platform properties.

## Autoscaling

Answers:

```text
Can the platform add capacity when demand increases?
```

## Pod-Kill Resilience

Answers:

```text
Can the platform continue operating and restore desired state when one application instance disappears?
```

Both are needed for a more complete view of runtime behavior.

---

# Monitoring During Load

Prometheus and Grafana were used alongside the load test to observe runtime behavior.

Relevant signals include:

```text
CPU utilization
Memory usage
Request rate
Request latency
Errors
Replica count
Application readiness
```

This allows performance results to be correlated with the actual state of the Kubernetes workload.

For example:

```text
Request load increases
        ↓
CPU rises
        ↓
HPA replica count increases
        ↓
Prometheus / Grafana show the change
```

For the monitoring implementation, see:

[Observability & Alerting](observability.md)

---

# Load Testing as Troubleshooting

The performance work followed an iterative process:

```text
Generate load
    ↓
Observe results
    ↓
Question the measurement path
    ↓
Remove port-forward bottleneck
    ↓
Run load inside Kubernetes
    ↓
Expose real application bottlenecks
    ↓
Investigate
    ↓
Adjust application/runtime behavior
    ↓
Retest
    ↓
Validate final result
```

This was more useful than treating Locust as a tool that only produces a requests-per-second number.

---

# What the Test Does Not Prove

The local load test should not be interpreted as proof of production-scale capacity.

It does not establish:

```text
Internet-scale throughput
Multi-region performance
Production AKS performance
Managed PostgreSQL performance
Real user traffic behavior
Long-duration soak-test behavior
```

The results apply to the local Kind environment.

The Azure architecture in the repository remains unprovisioned, so no performance claims are made for AKS or Azure Database for PostgreSQL.

---

# Validation Summary

The load-testing and resilience milestone validated:

```text
metrics-server operation
HPA CPU target behavior
Scale-up from 2 → 4 → 5 replicas
Automatic scale-down to 2 replicas
In-cluster Locust execution
150 concurrent users
3-minute sustained workload
29,286 total requests
0 failures in final sustained run
~165 req/s throughput
~1.2 s p95 latency
Application bottleneck investigation
CPU constraint investigation
Database connection-pool investigation
Connection timeout behavior
Unbounded query investigation
Pod-kill resilience
20,592 requests during pod-kill test
18 failed requests
0.09% failure rate
Automatic Kubernetes pod recreation
Continued traffic through remaining replicas
```

The milestone therefore validates both **capacity adaptation** and **partial workload failure recovery**.

---

# Relevant Files

```text
locustfile.py

loadtest/

charts/
└── sre-platform-app/

monitoring/
```

The Kubernetes chart contains the application resources and HPA configuration, while the Locust configuration defines the generated workload.

---

# Related Documentation

- [CI Pipeline & Security](ci-security.md)
- [Kubernetes & Helm](kubernetes-helm.md)
- [GitOps with ArgoCD](gitops.md)
- [Observability & Alerting](observability.md)
- [Distributed Tracing & Chaos Engineering](tracing-chaos.md)
- [Terraform & Azure](../terraform/README.md)