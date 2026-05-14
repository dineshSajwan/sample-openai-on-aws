# Quick Start: Pattern 3 — Full Observability

> **Note:** The analytics pipeline infrastructure (Kinesis, Glue, Athena, productivity platform integrations, QuickSight/Grafana dashboards) described in this guide is **coming soon**. The CloudFormation templates, Lambda functions, and integration configs referenced below are not yet included in this repository. The SQL queries and architecture documentation are provided as a preview of what will ship. Pattern 2 is fully functional today.

Add comprehensive analytics and productivity metrics on top of Pattern 2 in 30 minutes.

**Use this pattern if:**
- ✅ You need to prove AI ROI to leadership
- ✅ You need historical analytics (6+ months of trends)
- ✅ You need DORA/SPACE productivity metrics
- ✅ You have 500+ developers and need audit-ready reporting

---

## Overview

**What You're Adding:**
```
Pattern 2 Gateway
    ↓
OTel Metrics → CloudWatch
    ↓
Kinesis Firehose → S3 Data Lake
    ↓
Athena SQL Queries + Glue Data Catalog
    ↓
Jellyfish/LinearB/Waydev (optional)
```

**Time Required:** 30 minutes (Pattern 2 must be deployed first)

**Prerequisites:** Pattern 2 must be fully deployed and working

---

## Prerequisites

### Required

- [ ] **Pattern 2 deployed** — Gateway must be operational
- [ ] AWS permissions for Kinesis, Athena, Glue, S3, Lambda
- [ ] Gateway OTel metrics flowing to CloudWatch (verify first)

### Optional

- [ ] Productivity platform license (Jellyfish, LinearB, Waydev, Allstacks)
- [ ] Git repository access for code metrics correlation
- [ ] JIRA/Linear access for issue tracking correlation

---

## What Pattern 3 Adds

| Component | Purpose | Pattern 2 | Pattern 3 |
|-----------|---------|-----------|-----------|
| **Real-time Dashboard** | Live token usage, errors | ✅ CloudWatch | ✅ CloudWatch |
| **Historical Storage** | Long-term trends | ❌ 15 days retention | ✅ S3 (indefinite) |
| **SQL Analytics** | Custom queries | ❌ No | ✅ Athena |
| **Data Catalog** | Schema management | ❌ No | ✅ Glue |
| **Metric Aggregation** | Per-user/team rollups | ❌ No | ✅ Lambda |
| **Productivity Integration** | DORA/SPACE metrics | ❌ No | ✅ Guides |
| **ROI Reporting** | Executive dashboards | ❌ No | ✅ Athena views |

---

## Deployment

### Step 1: Verify Pattern 2 is Working

```bash
# 1. Check gateway is healthy
GATEWAY_URL=$(aws cloudformation describe-stacks \
  --stack-name codex-gateway \
  --region us-west-2 \
  --query 'Stacks[0].Outputs[?OutputKey==`GatewayURL`].OutputValue' \
  --output text)

curl "$GATEWAY_URL/health"
# Expected: {"status":"healthy"}

# 2. Verify OTel metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace Codex \
  --metric-name codex.turn.token_usage \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region us-west-2

# Expected: Non-empty Datapoints array
# If empty, Pattern 2 OTel is not configured
```

**If no metrics:** Deploy OTel collector first (see Pattern 2 guide)

---

### Step 2: Deploy Analytics Pipeline

**Option A: Using `cxwb` wizard** *(coming soon)*

```bash
# The 'cxwb analytics' sub-command is not yet available.
# Use Option B (manual CloudFormation) until it ships.
```

**Option B: Manual CloudFormation deployment** *(CloudFormation templates coming soon)*

```bash
cd deployment/infrastructure/

# 1. Create S3 bucket for data lake
BUCKET_NAME=codex-analytics-$(aws sts get-caller-identity --query Account --output text)

aws s3 mb s3://$BUCKET_NAME --region us-west-2

# 2. Deploy analytics pipeline stack
# NOTE: analytics-pipeline.yaml is coming soon
aws cloudformation deploy \
  --stack-name codex-analytics-pipeline \
  --template-file analytics-pipeline.yaml \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides \
      AnalyticsBucket="$BUCKET_NAME" \
      GatewayStackName=codex-gateway

# This creates:
# - Kinesis Firehose delivery stream
# - S3 bucket with partitioning (year/month/day/hour)
# - Glue Data Catalog database: codex_analytics
# - Glue Crawler: codex-metrics-crawler
# - Lambda functions for metric aggregation:
#   - active_users, top_users, token_by_model
#   - operations_count, cache_efficiency
#   - model_quota_usage, code_acceptance

# Wait 5-7 minutes
aws cloudformation wait stack-create-complete \
  --stack-name codex-analytics-pipeline \
  --region us-west-2
```

---

### Step 3: Configure CloudWatch → Kinesis Flow

```bash
# 1. Get Firehose ARN
FIREHOSE_ARN=$(aws cloudformation describe-stacks \
  --stack-name codex-analytics-pipeline \
  --region us-west-2 \
  --query 'Stacks[0].Outputs[?OutputKey==`FirehoseArn`].OutputValue' \
  --output text)

# 2. Create CloudWatch subscription filter
aws logs put-subscription-filter \
  --log-group-name /aws/lambda/codex-otel-collector \
  --filter-name codex-to-firehose \
  --filter-pattern "" \
  --destination-arn "$FIREHOSE_ARN" \
  --region us-west-2

# 3. Verify data flowing
aws firehose describe-delivery-stream \
  --delivery-stream-name codex-metrics \
  --region us-west-2 \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Expected: "ACTIVE"
```

---

### Step 4: Run Glue Crawler (Initial Data Discovery)

```bash
# 1. Wait 1 hour for first data batch to arrive in S3
# Firehose buffers for 60 seconds or 1MB, whichever comes first

# 2. Check S3 has data
aws s3 ls s3://$BUCKET_NAME/metrics/ --recursive

# Expected: Files like metrics/2026/05/11/10/data-*.parquet

# 3. Run Glue Crawler to discover schema
aws glue start-crawler --name codex-metrics-crawler

# Wait for crawler to complete (2-3 minutes)
aws glue get-crawler --name codex-metrics-crawler \
  --query 'Crawler.State'

# Expected: "READY"

# 4. Verify tables created
aws glue get-tables \
  --database-name codex_analytics \
  --region us-west-2 \
  --query 'TableList[*].Name'

# Expected: ["codex_metrics", "codex_tokens", "codex_operations"]
```

---

### Step 5: Deploy Athena Queries and Views

*(CloudFormation templates coming soon)*

```bash
cd deployment/infrastructure/

# NOTE: logs-insights-queries.yaml is coming soon
# 1. Deploy Athena saved queries
aws cloudformation deploy \
  --stack-name codex-athena-queries \
  --template-file logs-insights-queries.yaml \
  --region us-west-2 \
  --parameter-overrides \
      GlueDatabase=codex_analytics

# This creates saved queries:
# - top_users_last_30d
# - token_usage_by_model
# - cost_by_department
# - daily_active_users
# - code_acceptance_rate
# - cache_hit_rate_trend

# 2. Create Athena workgroup
aws athena create-work-group \
  --name codex-analytics \
  --configuration "{
    \"ResultConfigurationUpdates\": {
      \"OutputLocation\": \"s3://$BUCKET_NAME/athena-results/\"
    },
    \"EnforceWorkGroupConfiguration\": true
  }" \
  --region us-west-2
```

---

### Step 6: Test Analytics Queries

**Query 1: Top 10 Users by Token Consumption (Last 7 Days)**

```sql
-- Run in Athena console or via CLI
SELECT 
    user_id,
    SUM(input_tokens) as total_input,
    SUM(output_tokens) as total_output,
    SUM(input_tokens + output_tokens) as total_tokens,
    COUNT(*) as request_count,
    ROUND(SUM(input_tokens + output_tokens) * 0.000002, 2) as estimated_cost_usd
FROM codex_analytics.codex_metrics
WHERE timestamp >= date_add('day', -7, current_date)
GROUP BY user_id
ORDER BY total_tokens DESC
LIMIT 10;
```

**Query 2: Token Usage Trend by Model (Last 30 Days)**

```sql
SELECT 
    DATE_TRUNC('day', timestamp) as date,
    model,
    SUM(input_tokens) as input_tokens,
    SUM(output_tokens) as output_tokens,
    SUM(cached_input_tokens) as cached_tokens,
    ROUND(100.0 * SUM(cached_input_tokens) / NULLIF(SUM(input_tokens), 0), 2) as cache_hit_rate
FROM codex_analytics.codex_metrics
WHERE timestamp >= date_add('day', -30, current_date)
GROUP BY DATE_TRUNC('day', timestamp), model
ORDER BY date DESC, model;
```

**Query 3: Cost Attribution by Department**

```sql
SELECT 
    JSON_EXTRACT_SCALAR(metadata, '$.department') as department,
    SUM(input_tokens + output_tokens) as total_tokens,
    COUNT(DISTINCT user_id) as unique_users,
    ROUND(SUM(input_tokens + output_tokens) * 0.000002, 2) as estimated_cost_usd
FROM codex_analytics.codex_metrics
WHERE timestamp >= date_add('day', -30, current_date)
    AND JSON_EXTRACT_SCALAR(metadata, '$.department') IS NOT NULL
GROUP BY JSON_EXTRACT_SCALAR(metadata, '$.department')
ORDER BY total_tokens DESC;
```

**Query 4: Code Acceptance Rate (Last 30 Days)**

```sql
SELECT 
    DATE_TRUNC('day', timestamp) as date,
    SUM(CASE WHEN operation = 'write' AND accepted = true THEN 1 ELSE 0 END) as accepted_writes,
    SUM(CASE WHEN operation = 'write' THEN 1 ELSE 0 END) as total_writes,
    ROUND(100.0 * SUM(CASE WHEN operation = 'write' AND accepted = true THEN 1 ELSE 0 END) 
          / NULLIF(SUM(CASE WHEN operation = 'write' THEN 1 ELSE 0 END), 0), 2) as acceptance_rate
FROM codex_analytics.codex_operations
WHERE timestamp >= date_add('day', -30, current_date)
GROUP BY DATE_TRUNC('day', timestamp)
ORDER BY date DESC;
```

**Run via CLI:**

```bash
# Save query to file
cat > /tmp/query.sql <<'EOF'
SELECT user_id, SUM(input_tokens + output_tokens) as total_tokens
FROM codex_analytics.codex_metrics
WHERE timestamp >= date_add('day', -7, current_date)
GROUP BY user_id
ORDER BY total_tokens DESC
LIMIT 10;
EOF

# Execute query
QUERY_EXECUTION_ID=$(aws athena start-query-execution \
  --query-string file:///tmp/query.sql \
  --work-group codex-analytics \
  --result-configuration OutputLocation=s3://$BUCKET_NAME/athena-results/ \
  --query 'QueryExecutionId' \
  --output text \
  --region us-west-2)

# Wait for completion
aws athena get-query-execution \
  --query-execution-id "$QUERY_EXECUTION_ID" \
  --region us-west-2 \
  --query 'QueryExecution.Status.State'

# Get results
aws athena get-query-results \
  --query-execution-id "$QUERY_EXECUTION_ID" \
  --region us-west-2 \
  --output table
```

---

## Productivity Platform Integrations

### Option 1: Jellyfish

**What Jellyfish Provides:**
- DORA metrics (deployment frequency, lead time, MTTR, change fail rate)
- SPACE framework metrics (developer satisfaction, performance, activity, collaboration, efficiency)
- AI coding impact tracking (Codex usage → velocity correlation)

**Integration Steps:** *(coming soon — CloudFormation template not yet included)*

```bash
# NOTE: jellyfish-integration.yaml is coming soon
# 1. Create Jellyfish data export IAM role
cd deployment/infrastructure/

aws cloudformation deploy \
  --stack-name codex-jellyfish-integration \
  --template-file jellyfish-integration.yaml \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides \
      JellyfishAccountID="<jellyfish-aws-account>" \
      JellyfishExternalID="<external-id-from-jellyfish>" \
      AnalyticsBucket="$BUCKET_NAME"

# 2. Get role ARN
JELLYFISH_ROLE=$(aws cloudformation describe-stacks \
  --stack-name codex-jellyfish-integration \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text)

# 3. Configure in Jellyfish UI
# Settings → Integrations → AWS S3
# Role ARN: <paste JELLYFISH_ROLE>
# Bucket: s3://$BUCKET_NAME/metrics/
# Data format: Parquet
```

**Jellyfish Setup:** [docs/integrate-jellyfish.md](docs/integrate-jellyfish.md) *(coming soon)*

---

### Option 2: LinearB

**What LinearB Provides:**
- Engineering metrics dashboard
- AI adoption monitoring (Codex usage trends)
- ROI calculator (developer hours saved)
- Workflow automation (alert on quota exceeded)

**Integration Steps:**

```bash
# 1. Create Kinesis stream for real-time export
aws kinesis create-stream \
  --stream-name codex-linearb-export \
  --shard-count 1 \
  --region us-west-2

# 2. Subscribe LinearB to stream
# In LinearB UI:
# Settings → Data Sources → AWS Kinesis
# Stream ARN: arn:aws:kinesis:us-west-2:123456789012:stream/codex-linearb-export
# Access method: Cross-account IAM role

# 3. Create CloudWatch → Kinesis subscription
aws logs put-subscription-filter \
  --log-group-name /aws/lambda/codex-otel-collector \
  --filter-name codex-to-linearb \
  --filter-pattern '[metric_name = "codex.turn.token_usage"]' \
  --destination-arn arn:aws:kinesis:us-west-2:123456789012:stream/codex-linearb-export \
  --region us-west-2
```

**LinearB Setup:** [docs/integrate-linearb.md](docs/integrate-linearb.md) *(coming soon)*

---

### Option 3: Waydev

**What Waydev Provides:**
- Individual developer dashboards
- Team performance benchmarking
- AI Coach recommendations (usage optimization)
- Code quality metrics + Codex correlation

**Integration Steps:**

```bash
# 1. Create S3 export bucket for Waydev
WAYDEV_BUCKET=codex-waydev-export-$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://$WAYDEV_BUCKET --region us-west-2

# 2. Set up daily batch export
aws events put-rule \
  --name codex-waydev-daily-export \
  --schedule-expression "cron(0 2 * * ? *)" \
  --region us-west-2

# 3. Lambda function to export yesterday's data
# (See deployment/lambda-functions/waydev-exporter/)

# 4. Configure in Waydev UI
# Settings → Integrations → AWS S3
# Bucket: s3://$WAYDEV_BUCKET/
# Format: JSON
# Schedule: Daily
```

**Waydev Setup:** [docs/integrate-waydev.md](docs/integrate-waydev.md) *(coming soon)*

---

### Option 4: Allstacks

**What Allstacks Provides:**
- Delivery risk detection (agentic analysis)
- GenAI usage tracking across tools (Codex + Copilot + ChatGPT)
- Audit-ready compliance reports
- Forecast accuracy (velocity + AI impact)

**Integration Steps:**

```bash
# 1. Allstacks uses webhook-based ingestion
# Deploy API Gateway webhook endpoint
aws cloudformation deploy \
  --stack-name codex-allstacks-webhook \
  --template-file allstacks-webhook.yaml \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides \
      AllstacksAPIKey="<api-key-from-allstacks>"

# 2. Get webhook URL
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name codex-allstacks-webhook \
  --query 'Stacks[0].Outputs[?OutputKey==`WebhookURL`].OutputValue' \
  --output text)

# 3. Configure CloudWatch event rule
aws events put-rule \
  --name codex-allstacks-events \
  --event-pattern '{
    "source": ["aws.cloudwatch"],
    "detail-type": ["CloudWatch Alarm State Change"],
    "detail": {
      "alarmName": [{"prefix": "codex-"}]
    }
  }' \
  --region us-west-2

aws events put-targets \
  --rule codex-allstacks-events \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-west-2:123456789012:function:allstacks-webhook" \
  --region us-west-2
```

**Allstacks Setup:** [docs/integrate-allstacks.md](docs/integrate-allstacks.md) *(coming soon)*

---

## Executive Dashboards

### QuickSight Dashboard (Recommended)

**One-time setup:**

```bash
# 1. Create QuickSight account
# Go to: https://quicksight.aws.amazon.com/
# Sign up for Enterprise edition ($24/month/user)

# 2. Grant QuickSight access to Athena + S3
# QuickSight → Manage QuickSight → Security & permissions
# Add Athena and S3 bucket: $BUCKET_NAME

# 3. Create Athena data source
# QuickSight → Datasets → New dataset → Athena
# Data source name: codex-analytics
# Workgroup: codex-analytics

# 4. Import sample dashboard
cd deployment/infrastructure/quicksight/

aws quicksight create-dashboard \
  --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
  --dashboard-id codex-roi-dashboard \
  --name "Codex ROI Dashboard" \
  --source-entity file://dashboard-template.json \
  --region us-west-2

# 5. Share with executives
# QuickSight → Dashboards → Codex ROI Dashboard → Share
# Add email addresses
```

**Dashboard includes:**
- Monthly spend trend (actual + forecast)
- Active users by department
- Top 10 power users
- Token usage by model (stacked area chart)
- Cache hit rate (cost savings)
- Code acceptance rate (quality signal)
- Weekly change (WoW % change)

---

### Custom Grafana Dashboard

**If you prefer self-hosted dashboards:**

```bash
# 1. Deploy Grafana on ECS Fargate
cd deployment/infrastructure/

aws cloudformation deploy \
  --stack-name codex-grafana \
  --template-file grafana-dashboard.yaml \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides \
      NetworkStackName=codex-networking

# 2. Get Grafana URL
GRAFANA_URL=$(aws cloudformation describe-stacks \
  --stack-name codex-grafana \
  --query 'Stacks[0].Outputs[?OutputKey==`GrafanaURL`].OutputValue' \
  --output text)

# 3. Login (default: admin / admin)
open "$GRAFANA_URL"

# 4. Configure Athena data source
# Settings → Data sources → Add data source → Athena
# Authentication: AWS SDK Default
# Database: codex_analytics
# Workgroup: codex-analytics

# 5. Import dashboard
# Dashboards → Import → Upload JSON
# File: deployment/infrastructure/grafana/codex-dashboard.json
```

---

## Validation

### Check Data Pipeline

```bash
# 1. Verify CloudWatch → Firehose flow
aws cloudwatch get-metric-statistics \
  --namespace AWS/Firehose \
  --metric-name IncomingRecords \
  --dimensions Name=DeliveryStreamName,Value=codex-metrics \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --region us-west-2

# Expected: Sum > 0

# 2. Verify S3 data
aws s3 ls s3://$BUCKET_NAME/metrics/$(date +%Y/%m/%d)/ --recursive

# Expected: Parquet files written in last hour

# 3. Check Glue Data Catalog
aws glue get-table \
  --database-name codex_analytics \
  --name codex_metrics \
  --region us-west-2 \
  --query 'Table.StorageDescriptor.Columns[*].Name'

# Expected: [user_id, timestamp, model, input_tokens, output_tokens, ...]
```

### Test End-to-End Query

```bash
# Query data from last 24 hours
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) as total_requests, SUM(input_tokens + output_tokens) as total_tokens FROM codex_analytics.codex_metrics WHERE timestamp >= date_add('day', -1, current_date)" \
  --work-group codex-analytics \
  --result-configuration OutputLocation=s3://$BUCKET_NAME/athena-results/ \
  --region us-west-2

# Should return non-zero counts if data is flowing
```

---

## Troubleshooting

### Issue: No data in S3 after 1 hour

**Cause:** CloudWatch subscription filter not sending to Firehose

**Fix:**
```bash
# Check subscription filter exists
aws logs describe-subscription-filters \
  --log-group-name /aws/lambda/codex-otel-collector \
  --region us-west-2

# Verify destination ARN matches Firehose
# Re-create if needed (see Step 3)
```

### Issue: Glue Crawler finds no tables

**Cause:** S3 path structure doesn't match expected format

**Fix:**
```bash
# Check Firehose output format
aws firehose describe-delivery-stream \
  --delivery-stream-name codex-metrics \
  --query 'DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription.Prefix'

# Expected: metrics/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/

# Manually run crawler
aws glue start-crawler --name codex-metrics-crawler

# Check crawler logs
aws logs tail /aws-glue/crawlers --follow
```

### Issue: Athena query fails with "Table not found"

**Cause:** Glue Crawler hasn't run yet or failed

**Fix:**
```bash
# Check crawler status
aws glue get-crawler --name codex-metrics-crawler \
  --query 'Crawler.[State,LastCrawl.Status]'

# If FAILED, check CloudWatch logs
aws logs get-log-events \
  --log-group-name /aws-glue/crawlers \
  --log-stream-name codex-metrics-crawler
```

---

---

## Cleanup

```bash
# 1. Stop data ingestion
aws logs delete-subscription-filter \
  --log-group-name /aws/lambda/codex-otel-collector \
  --filter-name codex-to-firehose \
  --region us-west-2

# 2. Delete CloudFormation stacks
aws cloudformation delete-stack --stack-name codex-athena-queries --region us-west-2
aws cloudformation delete-stack --stack-name codex-analytics-pipeline --region us-west-2

# 3. Delete S3 data (CAUTION: Irreversible)
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# 4. Delete Athena workgroup
aws athena delete-work-group --work-group codex-analytics --recursive-delete-option
```

---

## Next Steps

- **Set up alerts:** CloudWatch alarms on cost thresholds
- **Automate reports:** Lambda function for weekly executive summary email
- **Correlate with JIRA:** Join Codex metrics with ticket data
- **Build ROI calculator:** Cost vs. developer hours saved

---

## Support

- **Documentation:** [README.md](README.md)
- **Issues:** [GitHub Issues](https://github.com/aws-samples/guidance-for-codex-on-aws/issues)
- **Analytics guide:** [docs/analytics.md](docs/analytics.md)
- **Monitoring guide:** [docs/operate-monitoring.md](docs/operate-monitoring.md)
