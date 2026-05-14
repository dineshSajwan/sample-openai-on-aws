# Native OTLP Monitoring Modes - Implementation Status

## ✅ Completed

### 1. Wizard Updates (`source/cxwb/commands/init.py`)
- ✅ Added `_prompt_monitoring()` function
- ✅ Integrated monitoring prompts into gateway flow
- ✅ Integrated monitoring prompts into IdC flow
- ✅ Support for 4 modes: hybrid, central, local, none

### 2. CloudFormation Updates (`deployment/infrastructure/otel-collector.yaml`)
- ✅ Added `EnableAnalytics` parameter
- ✅ Added `AnalyticsEnabled` and `AnalyticsDisabled` conditions
- ✅ Made `MetricsLogGroup` conditional
- ✅ Updated TaskRole IAM permissions:
  - Added `monitoring:PutMetricData`
  - Made logs permissions conditional

## 🚧 In Progress

### 3. OTel Collector Configuration (SSM Parameters)
Need to add two conditional SSM parameters in `otel-collector.yaml`:

#### A. OTelConfigOtlpOnly (when EnableAnalytics=false)
```yaml
extensions:
  health_check:
  sigv4auth:
    service: "monitoring"
    region: "${AWS::Region}"

exporters:
  otlphttp:
    endpoint: "https://monitoring.${AWS::Region}.amazonaws.com"
    auth:
      authenticator: sigv4auth
    tls:
      insecure: false

service:
  extensions: [health_check, sigv4auth]
  pipelines:
    metrics:
      exporters: [otlphttp]
```

#### B. OTelConfigDualExport (when EnableAnalytics=true)
Same as above plus:
```yaml
exporters:
  otlphttp: (same)
  awsemf:
    namespace: Codex
    log_group_name: /aws/codex/metrics
    # ... existing EMF config

service:
  pipelines:
    metrics:
      exporters: [otlphttp, awsemf]  # Both!
```

### 4. Deploy Command Updates (`source/cxwb/commands/deploy.py`)
- [ ] Skip networking/otel stacks when mode="local"
- [ ] Pass EnableAnalytics parameter based on profile
- [ ] Conditionally enable LiteLLM OTEL callbacks

### 5. Distribute Command Updates (`source/cxwb/commands/distribute.py`)
- [ ] Include local collector binary when mode in ["local", "hybrid"]
- [ ] Generate otel-local-config.yaml
- [ ] Update config.toml.fragment with [otel] block conditionally
- [ ] Generate start/stop collector scripts

### 6. Dashboard Updates (`deployment/infrastructure/codex-otel-dashboard.yaml`)
- [ ] Add MonitoringMode parameter
- [ ] Add conditional widget sections
- [ ] Migrate queries to PromQL

### 7. Documentation Updates
- [ ] QUICKSTART_PATTERN_GATEWAY.md
- [ ] QUICKSTART_PATTERN_IDC.md
- [ ] Add monitoring modes section

## 📋 TODO

### 8. Local Collector Implementation
- [ ] Create `deployment/scripts/build-local-collector.sh`
- [ ] Build multi-platform binaries (darwin-arm64, darwin-amd64, linux-amd64, windows-amd64)
- [ ] Create local collector config template
- [ ] Generate start/stop scripts

### 9. Testing
- [ ] Test local-only mode
- [ ] Test central-only mode
- [ ] Test hybrid mode
- [ ] Test analytics enabled/disabled

## File Changes Summary

```
Modified:
  source/cxwb/commands/init.py               ✅ DONE
  deployment/infrastructure/otel-collector.yaml  🚧 IN PROGRESS
  source/cxwb/commands/deploy.py             ⏳ TODO
  source/cxwb/commands/distribute.py         ⏳ TODO
  deployment/infrastructure/codex-otel-dashboard.yaml  ⏳ TODO
  QUICKSTART_PATTERN_GATEWAY.md              ⏳ TODO
  QUICKSTART_PATTERN_IDC.md                  ⏳ TODO

New Files:
  deployment/scripts/build-local-collector.sh     ⏳ TODO
  deployment/templates/otel-local-config.yaml     ⏳ TODO
  deployment/templates/start-collector.sh.template ⏳ TODO
  deployment/templates/stop-collector.sh.template  ⏳ TODO
```
