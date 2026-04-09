#!/usr/bin/env bash

cmd_trace() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    test)     trace_test "$@" ;;
    status)   trace_status "$@" ;;
    export)   trace_export "$@" ;;
    config)   trace_config "$@" ;;
    "")       trace_menu ;;
    *)
      error "trace: unknown subcommand: $subcommand"
      echo "  Usage: devops-desk trace [test|status|export|config]"
      exit 1 ;;
  esac
}

trace_menu() {
  local choice
  choice=$(printf '%s\n' \
    "config    Show current OTEL/Dash0 configuration" \
    "test      Send test spans to Dash0" \
    "status    Check Dash0 connectivity" \
    "export    Generate OTEL env var exports" \
    | fzf "${DD_FZF_OPTS[@]}" \
      --prompt="Tracing > " \
      --header="OpenTelemetry / Dash0 Operations" \
      --height=12) || return 0

  [[ -z "$choice" ]] && return
  cmd_trace "$(echo "$choice" | awk '{print $1}')"
}

# ─── OTEL Configuration ───────────────────────────────────────────────────────
trace_config() {
  local service="${1:-bi-advanced-analytics}"

  step "OTEL Configuration for service: $service"
  
  [[ -z "$OTEL_EXPORTER_OTLP_ENDPOINT" ]] && warning "OTEL_EXPORTER_OTLP_ENDPOINT not set"
  [[ -z "$OTEL_EXPORTER_OTLP_HEADERS" ]] && warning "OTEL_EXPORTER_OTLP_HEADERS not set"
  [[ -z "$OTEL_SERVICE_NAME" ]] && warning "OTEL_SERVICE_NAME not set"

  cat <<EOF

$(color_bold "Environment Variables:")
  OTEL_EXPORTER_OTLP_ENDPOINT:     ${OTEL_EXPORTER_OTLP_ENDPOINT:-not set}
  OTEL_EXPORTER_OTLP_HEADERS:      ${OTEL_EXPORTER_OTLP_HEADERS:+SET}
  OTEL_EXPORTER_OTLP_PROTOCOL:     ${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}
  OTEL_TRACES_EXPORTER:            ${OTEL_TRACES_EXPORTER:-otlp}
  OTEL_SERVICE_NAME:               ${OTEL_SERVICE_NAME:-not set}

$(color_bold "Dash0 Integration:")
  Endpoint: ingress.eu-west-1.aws.dash0.com:4317
  Protocol: gRPC (OTLP)
  Dataset:  dev (from headers)

EOF
}

# ─── Test Span Submission ─────────────────────────────────────────────────────
trace_test() {
  require_env > /dev/null
  local service="${1:-bi-advanced-analytics}"

  step "Sending test spans to Dash0 for service: $service"

  # Create inline test script
  local test_script
  test_script=$(cat <<'SCRIPT'
import sys
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
import os
import time

try:
    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "")
    headers = os.environ.get("OTEL_EXPORTER_OTLP_HEADERS", "")
    service_name = os.environ.get("OTEL_SERVICE_NAME", "test-service")
    
    if not endpoint or not headers:
        print("❌ OTEL_EXPORTER_OTLP_ENDPOINT or OTEL_EXPORTER_OTLP_HEADERS not set")
        sys.exit(1)
    
    # Create exporter
    exporter = OTLPSpanExporter(
        endpoint=endpoint,
        headers=dict(pair.split("=") for pair in headers.split(","))
    )
    
    # Create provider
    provider = TracerProvider()
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    
    # Create tracer and test span
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span("devops_desk_test_span") as span:
        span.set_attribute("test.timestamp", str(time.time()))
        span.set_attribute("service.name", service_name)
    
    # Flush
    provider.force_flush()
    print("✅ Test span sent successfully!")
    print(f"   Service: {service_name}")
    print(f"   Endpoint: {endpoint}")
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
SCRIPT
)

  echo "$test_script" | python3 - || error "Failed to send test span"
}

# ─── Dash0 Connectivity Status ────────────────────────────────────────────────
trace_status() {
  step "Checking Dash0 connectivity"

  # Simple connectivity test via curl
  local endpoint="ingress.eu-west-1.aws.dash0.com:4317"
  
  if nc -z "${endpoint%:*}" "${endpoint##*:}" 2>/dev/null; then
    success "Dash0 endpoint reachable: $endpoint"
  else
    warning "Dash0 endpoint check inconclusive (gRPC ports may not respond to TCP checks)"
  fi

  info "Full connectivity test requires actual span submission (use 'devops-desk trace test')"
}

# ─── Export OTEL Variables ────────────────────────────────────────────────────
trace_export() {
  local auth_token="${1:-}"
  local dataset="${2:-dev}"
  local service="${3:-bi-advanced-analytics}"

  if [[ -z "$auth_token" ]]; then
    info "Enter Dash0 Bearer token:"
    read -rs auth_token
    echo ""
  fi

  [[ -z "$auth_token" ]] && { error "Auth token required"; return 1; }

  step "Generating OTEL environment variables"

  cat <<EOF

# ─── OTEL Environment Variables for Dash0 ─────────────────────────────────

export OTEL_EXPORTER_OTLP_ENDPOINT="ingress.eu-west-1.aws.dash0.com:4317"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${auth_token},Dash0-Dataset=${dataset}"
export OTEL_SERVICE_NAME="${service}"
export OTEL_TRACES_EXPORTER="otlp"
export OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
export OTEL_RESOURCE_ATTRIBUTES="deployment.environment=$(state_get_env),host.name=\$(hostname)"

# ─── Load with:
# source <(devops-desk trace export)

EOF
}
