# Guidance for Codex on Amazon Bedrock

Run [OpenAI Codex](https://github.com/openai/codex) against [Amazon Bedrock](https://aws.amazon.com/bedrock/) with enterprise-grade identity, quota enforcement, and observability.

This guidance provides three deployment patterns — choose the one that matches your organization's needs for budget enforcement and analytics.

---

## Choose Your Pattern

**Start with this decision tree:**

```
Question 1: Do you need HARD quota enforcement?
(Blocking requests when users hit limits, not just alerts)

├── YES → Must use Pattern 2 or 3 (Gateway required)
│         Why: IdC cannot block requests mid-session
│         │
│         └── Need productivity analytics/ROI reporting?
│              ├── No  → Pattern 2: Governed Gateway
│              └── Yes → Pattern 3: Full Observability
│
└── NO → Question 2: Already use AWS IAM Identity Center?
          
          ├── YES → Pattern 1: Native AWS Access
          │         (Fastest: 5 min setup)
          │
          └── NO → Choose one:
                    
                    Option A: Pattern 1 (Set up IdC + SAML)
                    • Pro: Native AWS integration
                    • Con: 30-60 min one-time setup
                    
                    Option B: Pattern 2 (Use Gateway + OIDC)
                    • Pro: 15 min setup, no IdC needed
                    • Con: Additional infrastructure required
```

**Key Decision Factors:**

1. **Hard quotas require Gateway** — IdC issues credentials directly to users; AWS cannot revoke them mid-session
2. **If you have IdC already** — Pattern 1 is fastest (5 minutes)
3. **If you don't have IdC** — Choose between setting up IdC (native AWS integration) vs. Gateway (faster setup)

---

## Pattern Comparison

| Capability | Pattern 1 | Pattern 2 | Pattern 3 |
|------------|-----------|-----------|-----------|
| **Authentication** | SAML → IdC | OIDC → Gateway | OIDC → Gateway |
| **IAM Identity Center Required?** | ✅ Yes | ❌ No | ❌ No |
| **Path to Bedrock** | Codex → Bedrock (native AWS SDK) | Codex → Gateway → Bedrock | Codex → Gateway → Bedrock |
| **Developer Command** | `aws sso login` | `export OPENAI_API_KEY=...` | Same as Pattern 2 |
| **Per-user CloudTrail Audit** | ✅ Native | ✅ Gateway logs | ✅ Gateway logs |
| **Soft Alerts (CloudWatch)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Hard Budget Limits** | ❌ No | ✅ Yes | ✅ Yes |
| **Per-team Quotas** | ❌ No | ✅ Yes | ✅ Yes |
| **Rate Limiting (RPM/TPM)** | ❌ No | ✅ Yes | ✅ Yes |
| **Model Routing/Fallback** | ❌ No | ✅ Yes | ✅ Yes |
| **Historical Analytics (Athena)** | ❌ No | ❌ No | ✅ Yes |
| **Productivity Platform Integration** | ❌ No | ❌ No | ✅ Yes |
| **ROI Reporting** | ❌ No | ❌ No | ✅ Yes |
| **Setup Time** | 5-60 min | 15 min | Pattern 2 + 30 min |

---

## Pattern 1 — Native AWS Access

> **"Codex on Bedrock with corporate SSO. No API keys, no custom binaries."**

### Who This Is For

- ✅ Organizations already using AWS IAM Identity Center
- ✅ Teams willing to set up SAML federation (30-60 min one-time setup)
- ✅ Environments where soft monitoring (alerts, not blocking) is sufficient
- ❌ NOT for: Hard budget enforcement or FinOps-controlled environments

### What Developers Experience

1. Run `aws sso login` — browser opens to corporate login page
2. Authenticate with existing credentials (Okta, Azure AD, Google, etc.)
3. Use Codex normally — credentials handled automatically by AWS CLI

**No custom executables. No credential helpers. No Python required.**

### Architecture

```
Corporate IdP (Okta/Azure) → SAML → IAM Identity Center → AWS credentials → Bedrock
                                                              ↓
                                                     CloudTrail attribution
```

### What Gets Deployed

- IAM role with Bedrock model invocation policy
- IAM Identity Center permission set (if not already configured)
- Developer bundle: bash scripts + config snippets (~15 KB)

### Quick Start

**→ [QUICKSTART_PATTERN_IDC.md](QUICKSTART_PATTERN_IDC.md)**

**Prerequisites:**
- AWS account with IAM and CloudFormation permissions
- Amazon Bedrock activated in target regions
- Identity provider with SAML 2.0 support (Okta, Azure AD, etc.)
- AWS CLI v2 installed

**Deployment time:** 5 minutes (if IdC already set up) or 30-60 minutes (initial IdC setup)

---

## Pattern 2 — Governed Gateway

### Who This Is For

- ✅ Organizations that need hard per-user/per-team budget limits
- ✅ Teams where FinOps or platform team controls AI spend
- ✅ Environments requiring rate limiting (RPM/TPM enforcement)
- ✅ Organizations that don't use IdC and don't want to set it up

### What You Get

Everything in Pattern 1, plus:

- **OIDC self-service authentication** — Custom JWT middleware (no Enterprise license required)
- **Hard budget enforcement** — Gateway blocks requests when quota exceeded
- **Per-user and per-team token budgets** — Configurable via LiteLLM
- **Rate limiting** — Requests per minute (RPM) and tokens per minute (TPM)
- **Model access policies** — Control which teams can use which models
- **Automatic model fallback** — If primary model throttled or unavailable
- **Cost attribution** — Per user, team, or department for chargeback
- **Centralized policy management** — Update limits without touching developer machines

### Architecture

```
Corporate IdP (Okta/Azure) → OIDC/JWT → JWT Middleware → LiteLLM Gateway → Bedrock
                                              ↓              ↓
                                        User→key         Quota enforcement
                                        mapping          Rate limiting
                                        (DynamoDB)       Model routing
```

**Authentication Options:**
1. **Admin-Generated Keys** (simplest) — Admin creates keys via LiteLLM UI, shares with developers
2. **OIDC Self-Service** (scalable) — Developers generate keys via SSO portal using custom JWT middleware (no Enterprise license required)

### Gateway Implementation

This guidance uses **LiteLLM** deployed on ECS Fargate — open source, OpenAI-compatible, native Bedrock support, virtual keys per user/team, budget enforcement, OTel metrics.

### What Gets Deployed

- VPC with public/private subnets (or use existing VPC)
- ECS Fargate cluster running LiteLLM gateway
- Application Load Balancer for gateway ingress
- RDS Postgres or DynamoDB for gateway state
- Developer bundle: config snippets + gateway URL (~8 KB)


### Quick Start

**→ [QUICKSTART_PATTERN_GATEWAY.md](QUICKSTART_PATTERN_GATEWAY.md)**

---

## Pattern 3 — Full Observability

### Who This Is For

- ✅ Enterprises where leadership needs to justify AI tooling investment
- ✅ Engineering organizations tracking adoption across teams/languages/repos
- ✅ FinOps or HR teams that need defensible ROI numbers for budget decisions
- ✅ Organizations with 500+ developers requiring historical analytics

### What You Get

Everything in Pattern 2, plus:

**Infrastructure Observability:**
- OTel metrics to Amazon CloudWatch (native, no collector infrastructure)
- CloudWatch Query Studio dashboards with token consumption, latency, error rates
- Automatic anomaly detection on usage patterns
- Long-term historical storage via S3 + Athena

**Developer Productivity Analytics:**
- Token usage trends by user, team, model, language
- Code acceptance rates and suggestion quality metrics
- Session duration and usage pattern analysis
- SQL queries for custom reporting via Athena

**ROI Reporting:**
- Integration guides for Jellyfish, LinearB, Waydev, Allstacks
- DORA/SPACE metric correlation
- Cost vs. productivity impact analysis
- Executive dashboards for quarterly reviews

### Architecture

```
Corporate IdP → OIDC → LiteLLM Gateway → Bedrock
                           ↓
                       OTel Metrics
                           ↓
                   CloudWatch + Kinesis Firehose
                           ↓
                   S3 Data Lake + Athena
                           ↓
           Jellyfish/LinearB/Waydev (optional)
```

### What Gets Deployed

- Everything in Pattern 2
- Amazon CloudWatch native OTel configuration
- CloudWatch dashboards for token economics and model usage
- Kinesis Firehose → S3 → Athena pipeline
- AWS Glue Data Catalog for schema management
- Lambda functions for metric aggregation

### Quick Start

**→ [QUICKSTART_PATTERN_HYBRID.md](QUICKSTART_PATTERN_HYBRID.md)**

**Prerequisites:**
- Pattern 2 already deployed (required foundation)
- Kinesis, Athena, Glue permissions
- (Optional) Productivity platform license (Jellyfish, LinearB, etc.)

**Deployment time:** Pattern 2 + 30 minutes

**Cost:** Pattern 2 cost + ~$50-100/month (Kinesis + Athena + Lambda)

---

## Important Migration Notes

### Pattern 1 → Pattern 2 Migration

**This is NOT a configuration change — it requires re-deployment.**

| Aspect | Changes Required |
|--------|-----------------|
| **Authentication** | Switch from SAML (IdC) to OIDC (Gateway) |
| **IdP Setup** | Create new OIDC app in your IdP |
| **Developer Workflow** | Change from `aws sso login` to API key |
| **Codex Config** | Change `model_provider` from `amazon-bedrock` to `openai` |
| **CloudTrail** | Attribution changes from per-user to gateway IAM role |

**Migration time:** 2-4 hours infrastructure + 1 hour per 10 developers for reconfiguration

**Best practice:** Test with pilot group (5-10 users) before org-wide rollout

### Pattern 2 → Pattern 3 Migration

**This IS a configuration change — analytics layer adds on top of Pattern 2.**

| Aspect | Changes Required |
|--------|-----------------|
| **Infrastructure** | Deploy Kinesis/Athena stacks |
| **Developer Impact** | Zero (no changes to auth or config) |
| **Data Collection** | Starts immediately after deployment |

**Migration time:** 30 minutes

---

## Supported Models

| Model ID | Notes |
|----------|-------|
| `openai.gpt-5.4` | **Recommended default.** Served via Bedrock Mantle. |
| `openai.gpt-oss-120b` | GPT-OSS 120B (Converse-compatible). |
| `openai.gpt-oss-20b` | GPT-OSS 20B (Converse-compatible). |

**Regions:** Available in `us-east-1`, `us-east-2`, `us-west-2`

Full region × model matrix: **[docs/reference-regions.md](docs/reference-regions.md)**

---

## Documentation Map

### Getting Started
- **[Choose Your Pattern](#choose-your-pattern)** — Decision tree (start here)
- **[QUICKSTART_PATTERN_IDC.md](QUICKSTART_PATTERN_IDC.md)** — Native AWS Access deployment
- **[QUICKSTART_PATTERN_GATEWAY.md](QUICKSTART_PATTERN_GATEWAY.md)** — Governed Gateway deployment
- **[QUICKSTART_PATTERN_HYBRID.md](QUICKSTART_PATTERN_HYBRID.md)** — Full Observability deployment

### Architecture & Deployment
- **[docs/01-decide.md](docs/01-decide.md)** — Detailed pattern comparison
- **[docs/deploy-identity-center.md](docs/deploy-identity-center.md)** — Pattern 1 technical guide
- **[QUICKSTART_PATTERN_GATEWAY.md](QUICKSTART_PATTERN_GATEWAY.md)** — Pattern 2 technical guide (use quickstart instead)

### Operations
- **[docs/operate-monitoring.md](docs/operate-monitoring.md)** — Monitoring and cost attribution
- **[docs/operate-troubleshooting.md](docs/operate-troubleshooting.md)** — Common issues and fixes

### Reference
- **[docs/reference-regions.md](docs/reference-regions.md)** — Supported regions and models

---

## Quick Setup with `cxwb` Wizard

All patterns can be deployed using the guided `cxwb` wizard:

```bash
cd source/
uv sync
uv run cxwb init                        # Pick pattern, answer prompts
uv run cxwb deploy --profile <name>     # Deploy CloudFormation stacks
uv run cxwb distribute --profile <name> # Generate developer bundles
```

**Supported deployment paths:**
- IdC + new stacks (Pattern 1)
- IdC + existing stacks (Pattern 1, BYO IdC)
- Gateway + new stacks (Pattern 2/3)
- Gateway + existing stacks (Pattern 2/3, BYO Gateway)

---

## Prerequisites

### For Administrators (Deployment)

**Software:**
- Python 3.10-3.13
- uv (package manager - [install guide](https://docs.astral.sh/uv/getting-started/installation/))
- AWS CLI v2
- Git
- Docker (for Pattern 2/3 gateway deployments)

**AWS Permissions:**
- CloudFormation stack creation
- IAM role and policy creation
- (Pattern 1) IAM Identity Center management
- (Pattern 2/3) ECS, VPC, ALB, RDS permissions
- (Pattern 3) Kinesis, Athena, Glue permissions

**Identity Provider:**
- (Pattern 1) SAML 2.0 support (Okta, Azure AD, Auth0, Google)
- (Pattern 2/3) OIDC support (Okta, Azure AD, Auth0, Cognito)

### For Developers (End Users)

**Pattern 1:**
- AWS CLI v2 installed
- Web browser for SSO authentication
- No Python, Poetry, or Git required

**Pattern 2/3:**
- Web browser for gateway authentication
- No AWS CLI required
- No Python, Poetry, or Git required

---

## Common Scenarios

### Scenario 1: Small Team, Already Use IdC
**Recommended:** Pattern 1

- Setup time: 5 minutes
- Cost: $0
- Why: Fastest, leverages existing infrastructure

### Scenario 2: Mid-Size Team, Need Budget Control
**Recommended:** Pattern 2

- Setup time: 15 minutes  
- Cost: ~$100-150/month
- Why: Only way to enforce hard quotas

### Scenario 3: Enterprise, Need ROI Reporting
**Recommended:** Pattern 3

- Setup time: Pattern 2 + 30 minutes
- Cost: ~$150-250/month
- Why: Leadership requires productivity metrics

### Scenario 4: Startup, No IdC, No Budget for Gateway
**Recommended:** Pattern 1 (set up IdC)

- Setup time: 30-60 minutes (one-time)
- Cost: $0
- Why: Clean architecture, no ongoing costs

---

## Frequently Asked Questions

**Can I migrate from Pattern 1 to Pattern 2 later?**

Not without re-deployment. Pattern 2 uses different authentication (OIDC vs. SAML) and routing architecture (Gateway vs. direct Bedrock). If you anticipate needing quotas within 12 months, start with Pattern 2.

**Do developers need to install anything?**

- Pattern 1: AWS CLI v2 (if not already installed)
- Pattern 2/3: Nothing (web-based authentication)

**Does Pattern 2 add latency?**

Yes, single-digit milliseconds (typically <10ms) as requests route through the gateway. Not noticeable for Codex use cases.

**What does Pattern 2 cost to run?**

~$100-150/month: ECS Fargate (~$70), ALB (~$20), RDS Postgres (~$30). LiteLLM is open source (no license fee).

**Are AWS GovCloud regions supported?**

Yes. All patterns support AWS GovCloud (US) and commercial regions where Bedrock is available.

**Where do I report issues?**

→ [GitHub Issues](https://github.com/aws-samples/guidance-for-codex-on-aws/issues)

---

## License

This guidance is licensed under [MIT](LICENSE).

---

## Related Resources

- **[OpenAI Codex](https://github.com/openai/codex)** — Official Codex documentation
- **[Amazon Bedrock](https://aws.amazon.com/bedrock/)** — AWS managed AI service
- **[LiteLLM](https://www.litellm.ai/)** — Open-source LLM gateway
- **[AWS IAM Identity Center](https://aws.amazon.com/iam/identity-center/)** — AWS SSO service
