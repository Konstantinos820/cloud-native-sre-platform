"""
Prometheus instrumentation.

Two kinds of metrics live here:
  1. Generic HTTP metrics (latency + request count) - the "four golden
     signals" building blocks, broken down by method/path/status.
  2. A business metric (user_registrations_total) to show that SRE
     metrics can track product value, not just infrastructure health.
"""

from prometheus_client import Counter, Histogram

# --- HTTP / infrastructure metrics -----------------------------------------

HTTP_REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total number of HTTP requests processed.",
    labelnames=("method", "path", "status_code"),
)

HTTP_REQUEST_DURATION_SECONDS = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds.",
    labelnames=("method", "path"),
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10),
)

# --- Business metrics --------------------------------------------------------

USER_REGISTRATIONS_TOTAL = Counter(
    "user_registrations_total",
    "Total number of successfully registered users (business metric).",
)