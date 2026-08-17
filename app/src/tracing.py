"""
OpenTelemetry Tracing Setup.
Initializes the TracerProvider and exports spans to the OTLP exporter (Tempo/Collector).
"""

import logging

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from src.config import settings

logger = logging.getLogger(__name__)


def setup_tracing() -> None:
    if not settings.OTEL_TRACES_ENABLED:
        logger.info("OpenTelemetry tracing is disabled.")
        return

    logger.info("Initializing OpenTelemetry Tracing...")

    resource = Resource.create(
        {
            "service.name": settings.OTEL_SERVICE_NAME,
            "service.version": settings.APP_VERSION,
        }
    )

    provider = TracerProvider(resource=resource)

    # Send traces over OTLP gRPC endpoint
    processor = BatchSpanProcessor(
        OTLPSpanExporter(endpoint=settings.OTEL_EXPORTER_OTLP_ENDPOINT, insecure=True)
    )
    provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)

    logger.info("OpenTelemetry Tracing initialized successfully.")
