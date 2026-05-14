# Local OTEL Collector Testing Guide

## Overview

This guide walks through testing the local OTEL collector implementation with CloudWatch native OTLP support.

## Prerequisites

- AWS account with CloudWatch access
- AWS CLI configured with SSO
- Python 3.10+ with uv
- OpenAI Codex installed

## Testing Steps

### 1. Download OTEL Collector Binary

```bash
cd deployment/scripts
./build-local-collector.sh --platform darwin-arm64  # Or your platform
# Available: darwin-arm64, darwin-amd64, linux-amd64, windows-amd64

# Verify binary downloaded
ls -lh ../binaries/
```

### 2. Initialize Profile with Local Monitoring

```bash
cd source
uv run cxwb init

# Selections:
# - Deployment path: LiteLLM Gateway — deploy new
# - Region: us-east-1
# - Enable monitoring: Yes
# - Monitoring mode: Local collectors only  ← This is now default
# - Profile name: test-local-otel
```

### 3. Build Bundle (No Infrastructure Deployment)

```bash
# Since we're using local-only mode, we don't need to deploy
# Just generate the bundle

uv run cxwb distribute --profile test-local-otel --bucket my-test-bucket

# Or use local directory:
# Edit distribute.py to support --local flag for testing
```

### 4. Manual Bundle Creation (For Testing)

```bash
# Create test bundle manually
mkdir -p /tmp/codex-test-bundle

# Run gateway config generator with local OTEL
../deployment/scripts/generate-codex-gateway-config.sh \
  --gateway-url https://your-gateway.example.com/v1 \
  --enable-local-otel \
  --aws-region us-east-1 \
  --user-email test@example.com \
  --outdir /tmp/codex-test-bundle

# Copy collector files
cp ../deployment/binaries/otelcol-local-darwin-arm64 /tmp/codex-test-bundle/otelcol-local
cp ../deployment/templates/otel-local-config.yaml /tmp/codex-test-bundle/otel-config.yaml
cp ../deployment/templates/start-collector.sh.template /tmp/codex-test-bundle/start-collector.sh
cp ../deployment/templates/stop-collector.sh.template /tmp/codex-test-bundle/stop-collector.sh
cp ../deployment/templates/collector-status.sh.template /tmp/codex-test-bundle/collector-status.sh

# Make scripts executable
chmod +x /tmp/codex-test-bundle/*.sh
chmod +x /tmp/codex-test-bundle/otelcol-local

# Substitute placeholders
cd /tmp/codex-test-bundle
sed -i '' 's/__AWS_REGION__/us-east-1/g' otel-config.yaml start-collector.sh stop-collector.sh collector-status.sh
sed -i '' 's/__USER_EMAIL__/test@example.com/g' otel-config.yaml collector-status.sh
sed -i '' 's/__USER_ID__/testuser/g' otel-config.yaml
sed -i '' 's/__AWS_PROFILE__/default/g' start-collector.sh
```

### 5. Install Collector Locally

```bash
cd /tmp/codex-test-bundle

# Create directories
mkdir -p ~/.codex/otel

# Copy files
cp otelcol-local ~/.codex/otel/
cp otel-config.yaml ~/.codex/otel/
cp start-collector.sh ~/.codex/otel/
cp stop-collector.sh ~/.codex/otel/
cp collector-status.sh ~/.codex/otel/
chmod +x ~/.codex/otel/*.sh
```

### 6. Configure AWS Credentials

```bash
# Ensure AWS SSO is logged in
aws sso login --profile your-profile

# Test credentials
aws sts get-caller-identity

# Verify monitoring service permission
# The SigV4 auth will use your current credentials
```

### 7. Start Collector

```bash
~/.codex/otel/start-collector.sh

# Expected output:
# Starting OTEL collector...
# ✓ OTEL collector started (PID 12345)
#   Sending metrics to: CloudWatch (region: us-east-1)
#   Logs: /Users/you/.codex/otel/otelcol.log
```

### 8. Check Collector Status

```bash
~/.codex/otel/collector-status.sh

# Expected output:
# ✓ Collector running
#   PID: 12345
#   Started: Wed May 14 10:30:00 2026
#   Memory: 45MB
#   Region: us-east-1
#   User: test@example.com
```

### 9. Send Test Metrics

You can test in two ways:

#### Option A: Use Codex (If Available)

```bash
# Configure Codex to use local OTEL
# Add to ~/.codex/config.toml:

[otel]
environment = "prod"
exporter = { otlp-http = {
  endpoint = "http://localhost:4318/v1/metrics",
  protocol = "binary"
}}

# Run Codex command
codex chat "Hello world"
```

#### Option B: Send Test OTLP Manually

```bash
# Install grpcurl for testing
brew install grpcurl  # macOS
# or apt-get install grpcurl  # Linux

# Send test metric
curl -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "resourceMetrics": [{
      "resource": {
        "attributes": [{
          "key": "service.name",
          "value": {"stringValue": "test"}
        }]
      },
      "scopeMetrics": [{
        "metrics": [{
          "name": "test.counter",
          "unit": "1",
          "sum": {
            "dataPoints": [{
              "asInt": "1",
              "timeUnixNano": "'$(date +%s)000000000'"
            }],
            "aggregationTemporality": 2,
            "isMonotonic": true
          }
        }]
      }]
    }]
  }'
```

### 10. Verify Metrics in CloudWatch

```bash
# Wait 1-2 minutes for metrics to appear

# Check CloudWatch Metrics console:
# https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2:

# Or use AWS CLI:
aws cloudwatch list-metrics --namespace test --region us-east-1

# Query with PromQL (if using dashboard):
# sum({__name__="test.counter"})
```

### 11. Check Collector Logs

```bash
tail -f ~/.codex/otel/otelcol.log

# Look for:
# - "Everything is ready. Begin running and processing data."
# - Export success messages
# - No authentication errors
```

### 12. Stop Collector

```bash
~/.codex/otel/stop-collector.sh

# Expected output:
# Stopping OTEL collector (PID 12345)...
# ✓ Collector stopped
```

## Troubleshooting

### Collector Won't Start

```bash
# Check credentials
aws sts get-caller-identity

# Check if port 4318 is available
lsof -i :4318

# Check logs
cat ~/.codex/otel/otelcol.log
```

### Authentication Errors

```
Error: "SignatureDoesNotMatch" or "AccessDenied"
```

**Fix:**
- Ensure `aws sso login` is run
- Verify IAM permissions include `monitoring:PutMetricData`
- Check region matches in config

### Metrics Not Appearing

```bash
# Verify collector is running
~/.codex/otel/collector-status.sh

# Check if metrics are being received
tail ~/.codex/otel/otelcol.log | grep "Metric"

# Try sending test metric manually (Option B above)

# Check CloudWatch Metrics with AWS CLI
aws cloudwatch list-metrics --region us-east-1
```

### High Memory Usage

The collector should use ~30-50MB. If higher:
- Check batch settings in otel-config.yaml
- Reduce batch timeout
- Check for metric explosion (too many labels)

## Success Criteria

✅ Collector starts without errors  
✅ Collector status shows running  
✅ No authentication errors in logs  
✅ Test metrics sent successfully  
✅ Metrics visible in CloudWatch console  
✅ PromQL queries return data (if dashboard deployed)  
✅ Collector stops cleanly  

## Next Steps

After verifying local collector works:

1. **Test with Real Codex Usage**
   - Configure Codex with [otel] block
   - Run actual coding sessions
   - Verify metrics show up

2. **Create Dashboard**
   - Deploy PromQL dashboard (if not using local-only)
   - Create queries for token usage, latency, errors

3. **Test on Multiple Platforms**
   - macOS (ARM + Intel)
   - Linux
   - Windows

4. **Prepare for Production**
   - Document IAM permission requirements
   - Create user onboarding guide
   - Set up automated bundle distribution

## Files Modified in This Implementation

```
✅ source/cxwb/commands/init.py               - Wizard with monitoring modes
✅ deployment/infrastructure/otel-collector.yaml  - CloudFormation updates
✅ deployment/scripts/build-local-collector.sh    - Binary download script
✅ deployment/templates/otel-local-config.yaml    - Collector config template
✅ deployment/templates/start-collector.sh        - Start script
✅ deployment/templates/stop-collector.sh         - Stop script
✅ deployment/templates/collector-status.sh       - Status script
✅ deployment/scripts/generate-codex-gateway-config.sh - Add OTEL config
✅ source/cxwb/commands/distribute.py          - Bundle generation
✅ QUICKSTART_PATTERN_GATEWAY.md              - Documentation
```

## Support

If you encounter issues:
1. Check logs: `~/.codex/otel/otelcol.log`
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Test OTLP endpoint: Send manual metric
4. Check CloudWatch permissions
5. Review CloudFormation events if using central collector
