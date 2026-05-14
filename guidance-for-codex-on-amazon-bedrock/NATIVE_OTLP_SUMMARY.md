# Native OTLP Monitoring Implementation - Summary

## What's Been Implemented

### 1. Wizard Configuration ✅

**File:** `source/cxwb/commands/init.py`

Added monitoring mode selection with 4 options:
- **Hybrid** - Local + Central collectors (complete visibility)
- **Central only** - Server-side metrics, requires ECS infrastructure
- **Local only** - Client-side metrics, no ECS infrastructure
- **None** - Disable monitoring

**User Experience:**
```bash
uv run cxwb init

? Enable OpenTelemetry monitoring? Yes
? Monitoring mode:
  ❯ Hybrid (local + central collectors) - Complete visibility
    Central collector only - Server-side metrics from gateway
    Local collectors only - Client-side metrics, no ECS infrastructure
    None - Disable monitoring
```

### 2. CloudFormation Template Updates (Partial) ✅

**File:** `deployment/infrastructure/otel-collector.yaml`

- Added `EnableAnalytics` parameter (true/false)
- Added conditions: `AnalyticsEnabled`, `AnalyticsDisabled`
- Made `MetricsLogGroup` conditional (only created when analytics enabled)
- Updated IAM permissions:
  - Added `monitoring:PutMetricData` for native OTLP
  - Made logs permissions conditional based on analytics

---

## What Needs To Be Completed

### Critical Path Items

#### 1. Complete OTel Collector Config (HIGH PRIORITY)

**File:** `deployment/infrastructure/otel-collector.yaml`

Need to replace the existing `OTelConfig` SSM parameter with TWO conditional parameters:

**A. Add new `OTelConfigOtlpOnly` (Condition: AnalyticsDisabled):**
- Add `sigv4auth` extension
- Replace `awsemf` exporter with `otlphttp`:
  - endpoint: `https://monitoring.${AWS::Region}.amazonaws.com`
  - auth: sigv4auth
- Update service pipelines to use `[otlphttp]`

**B. Add new `OTelConfigDualExport` (Condition: AnalyticsEnabled):**
- Same as above BUT:
- Keep both exporters: `[otlphttp, awsemf]`
- EMF logs for analytics pipeline

**C. Remove old `OTelConfig`** (currently unconditional)

#### 2. Deploy Command Logic

**File:** `source/cxwb/commands/deploy.py`

```python
def deploy_command(profile_name):
    p = profile.load(profile_name)
    mode = p.get("monitoring", {}).get("mode", "none")
    
    # Skip otel stacks if local-only
    if mode in ["central", "hybrid"]:
        deploy_networking_stack(p)
        deploy_otel_collector_stack(p, 
            enable_analytics=p["monitoring"]["analytics_enabled"])
    
    # Deploy gateway with conditional OTEL
    deploy_gateway_stack(p, otel_enabled=(mode in ["central", "hybrid"]))
    
    # Deploy dashboard if monitoring enabled
    if mode != "none":
        deploy_dashboard_stack(p, mode=mode)
```

#### 3. Bundle Generation

**File:** `source/cxwb/commands/distribute.py`

```python
def generate_bundle(profile_name):
    p = profile.load(profile_name)
    mode = p.get("monitoring", {}).get("mode", "none")
    
    # Base config
    generate_gateway_config(p, outdir)
    
    # Add local collector if needed
    if mode in ["local", "hybrid"]:
        add_local_collector_binary(outdir, platforms=[
            "darwin-arm64", "darwin-amd64",
            "linux-amd64", "windows-amd64"
        ])
        generate_local_otel_config(outdir, p)
        generate_collector_scripts(outdir)  # start/stop scripts
        add_codex_otel_config(outdir)  # [otel] block in config.toml
```

#### 4. Dashboard Migration

**File:** `deployment/infrastructure/codex-otel-dashboard.yaml`

- Add `MonitoringMode` parameter
- Add conditional sections for client/server metrics
- Migrate all queries from CloudWatch SEARCH to PromQL:
  ```yaml
  # Before
  SEARCH('Namespace="Codex" MetricName="token_usage"', 'Sum')
  
  # After
  {"language": "PromQL", "query": "sum({\"codex.token.usage\"})"}
  ```

#### 5. Local Collector Build Script

**New File:** `deployment/scripts/build-local-collector.sh`

Build ADOT collector binary for multiple platforms:
```bash
#!/usr/bin/env bash
# Builds ADOT collector for darwin-arm64, darwin-amd64, linux-amd64, windows-amd64
# Uses Docker buildx for cross-compilation
# Outputs to deployment/binaries/
```

#### 6. Local Collector Config Template

**New File:** `deployment/templates/otel-local-config.yaml`

```yaml
extensions:
  health_check:
  sigv4auth:
    service: "monitoring"
    region: "${AWS_REGION}"

receivers:
  otlp:
    protocols:
      http:
        endpoint: 127.0.0.1:4318

processors:
  attributes:
    actions:
      - key: user.email
        value: "${USER_EMAIL}"
        action: insert
  resource:
    attributes:
      - key: source
        value: "client"
        action: insert

exporters:
  otlphttp:
    endpoint: "https://monitoring.${AWS_REGION}.amazonaws.com"
    auth:
      authenticator: sigv4auth

service:
  extensions: [health_check, sigv4auth]
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [attributes, resource]
      exporters: [otlphttp]
```

#### 7. Documentation Updates

**Files to update:**
- `QUICKSTART_PATTERN_GATEWAY.md` - Add monitoring modes section
- `QUICKSTART_PATTERN_IDC.md` - Add monitoring modes section
- `README.md` - Update architecture descriptions

**Key sections to add:**

```markdown
## Monitoring Modes

### Central Collector Only
- LiteLLM gateway sends metrics to central ECS collector
- Requires networking + ECS infrastructure
- Tracks: API usage, costs, quotas, rate limits, gateway health
- Missing: Client-side E2E latency, local tool usage

### Local Collectors Only
- Each developer runs local collector binary
- No ECS infrastructure required
- Tracks: E2E latency, client operations, local tools
- Missing: Server-side visibility (quotas, rate limits)

### Hybrid (Recommended)
- Central collector for gateway metrics
- Local collectors for client metrics
- Complete observability
- Single CloudWatch dashboard shows both

### Configuration
Choose mode during `cxwb init`:
- Hybrid: Complete visibility
- Central: Server-side only
- Local: Client-side only, no ECS infrastructure
- None: Disable monitoring
```

---

## Implementation Effort Estimate

| Task | Effort | Priority | Status |
|------|--------|----------|--------|
| OTel collector SSM configs | 2 hours | HIGH | 🚧 25% |
| Deploy command logic | 2 hours | HIGH | ⏳ |
| Bundle generation | 3 hours | HIGH | ⏳ |
| Local collector build script | 4 hours | MEDIUM | ⏳ |
| Dashboard PromQL migration | 3 hours | MEDIUM | ⏳ |
| Documentation updates | 2 hours | MEDIUM | ⏳ |
| Testing all modes | 4 hours | HIGH | ⏳ |
| **TOTAL** | **~20 hours** | | **~5% complete** |

---

## Next Steps

### Option 1: Complete Full Implementation (~2-3 days)
Continue implementing all remaining items above.

### Option 2: MVP First (Central-Only with Native OTLP)
1. Complete OTel collector native OTLP config (2 hours)
2. Update deploy command for central-only (1 hour)  
3. Basic dashboard PromQL (2 hours)
4. Test central-only mode (1 hour)
**Total: ~6 hours**

Then iterate to add local/hybrid modes later.

### Option 3: Code Review & Planning
- Review changes made so far
- Refine design based on feedback
- Plan remaining implementation

---

## Files Modified So Far

```
✅ source/cxwb/commands/init.py
   - Added _prompt_monitoring()
   - Integrated into gateway and IdC flows

🚧 deployment/infrastructure/otel-collector.yaml  
   - Added EnableAnalytics parameter
   - Added conditional MetricsLogGroup
   - Updated IAM permissions
   - REMAINING: Add dual SSM parameters with native OTLP config

📝 IMPLEMENTATION_PLAN.md (created)
📝 NATIVE_OTLP_SUMMARY.md (this file)
```

---

## Recommendation

**Start with MVP (Option 2):**
1. Finish native OTLP for central collector
2. Test with existing gateway pattern
3. Validate CloudWatch native OTLP ingestion
4. Then add local/hybrid modes in subsequent PR

This de-risks the core native OTLP integration before adding complexity of multi-mode support.
