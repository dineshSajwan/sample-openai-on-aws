# Deploy — Gateway (Alternative)

Deploy an OpenAI-compatible proxy in front of Bedrock. Developers point Codex at
the gateway using a per-user API key; the gateway authenticates to Bedrock with
its ECS task role. Use this path when you need hard per-user budgets or a
single enforcement point that is not tied to AWS identity.

If you only need per-user *attribution* and already run IdC, prefer
`deploy-identity-center.md` — it is simpler and less expensive.

## The pattern

```
Developer (Codex CLI)
    │  Authorization: Bearer <per-user-key-or-JWT>
    ▼
ALB (HTTPS, WAF / OIDC / JWT validation)
    ▼
Gateway (ECS Fargate task)           ── OTel ──▶  OTel collector ──▶ CloudWatch
    │   auth to Bedrock via task role
    ▼
Amazon Bedrock (Converse / InvokeModel)
```

Two authentication hops: **developer → gateway** (JWT or per-user API key) and
**gateway → Bedrock** (ECS task IAM role). No AWS credentials reach developer
machines, and there is no binary to sign, notarize, or distribute.

## What to look for in a gateway

A production-grade gateway for this use case must cover all of the following:

- **Per-user identity on every request.** JWT validation at the ALB or in the
  gateway, or a master key that generates per-user API keys. You need a stable
  identifier for cost attribution and quota enforcement.
- **Hard per-user budgets with automatic cutoff.** Not merely alerts — a 429 when
  a user reaches the limit. This is the primary reason to run a gateway.
- **OTel emission on success *and* failure.** Every call should produce a span
  or metric with the user-id dimension. Confirm that the gateway emits
  failure events before relying on alarms.
- **Signed, auditable distribution of client config.** What you provide to developers
  is a URL plus a per-user secret — so secret rotation, revocation, and
  bootstrap require a defined process. Do not email keys.
- **GovCloud posture.** If you need FedRAMP: is the gateway image available in
  GovCloud ECR mirrors, does the authentication stack work without the commercial IdC
  control plane, and can the OTel pipeline write to GovCloud CloudWatch.

If a candidate meets all of the above, it will work here. The reference below uses
LiteLLM, but the structure is the same for every alternative.

## LiteLLM reference implementation

The reference implementation ships in this repository under `deployment/litellm/`. Use it as-is or as a
blueprint for a different gateway.

> **Scope note.** This reference is deliberately minimal — a single-provider (Bedrock-only)
> Codex-scoped gateway. For a production-grade, multi-provider LiteLLM deployment, see the
> AWS Solutions Library guidance:
> [Guidance for a Multi-Provider Generative AI Gateway on AWS](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws).

### Prerequisites

- AWS account with IAM, ECS, RDS, ECR, and Bedrock access.
- Bedrock activated in the target region. See [reference-regions.md](reference-regions.md) for the current model × region matrix.
- Docker (local) + AWS CLI v2 (control host).
- The OTel networking and collector stacks already deployed — the gateway reuses
  their VPC and collector endpoint. Deploy them first with:

  ```bash
  deployment/scripts/deploy-otel-stack.sh --region us-west-2
  ```

### 1. Build and push the LiteLLM image

The configuration is embedded into the image so the running task requires no external
configuration fetch. If you need to change models or callbacks, rebuild and redeploy.

```bash
REGION=us-west-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/codex-litellm

aws ecr create-repository --repository-name codex-litellm --region $REGION
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ECR_URI

docker build -t $ECR_URI:latest deployment/litellm
docker push $ECR_URI:latest
```

### 2. Deploy the gateway stack

```bash
aws cloudformation deploy \
  --stack-name codex-litellm-gateway \
  --template-file deployment/litellm/ecs/litellm-ecs.yaml \
  --capabilities CAPABILITY_IAM \
  --region $REGION \
  --parameter-overrides \
    NetworkingStackName=codex-otel-networking \
    OtelStackName=codex-otel-collector \
    AwsRegion=$REGION \
    LiteLLMImage=$ECR_URI:latest \
    LiteLLMMasterKey=sk-$(openssl rand -hex 16) \
    DBPassword=$(openssl rand -hex 16) \
    AllowedCidr=10.0.0.0/16
```

Notes on the parameter defaults (hardening TODOs):

- `AwsRegion` defaults to `us-east-1`; **always override** it to the region
  where Bedrock is enabled.
- `AllowedCidr` defaults to `10.0.0.0/16` (VPC-internal). To reach the gateway
  from outside the VPC, add a temporary `/32` ingress rule to the ALB security
  group, then remove it afterward.
- The template's `litellm_config.yaml` ships a `bedrock/openai.gpt-5.4`
  placeholder. The `gpt-oss-120b` alias is a suitable alternative for plumbing tests.

### 3. Verify the gateway is reachable

```bash
GATEWAY=$(aws cloudformation describe-stacks \
  --stack-name codex-litellm-gateway --region $REGION \
  --query "Stacks[0].Outputs[?OutputKey=='GatewayEndpoint'].OutputValue" \
  --output text)

curl -s "$GATEWAY/health/liveness" -H "Authorization: Bearer $MASTER_KEY"
```

### 4. Generate per-user keys

```bash
curl -sX POST "$GATEWAY/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"alice@example.com","max_budget":50,"budget_duration":"30d"}'
```

For self-service SSO-generated keys (LiteLLM Enterprise), configure
`GENERIC_CLIENT_ID` / `GENERIC_AUTHORIZATION_ENDPOINT` / `PROXY_BASE_URL` on
the task and direct users to `$GATEWAY/sso/key/generate`.

### 5. Configure Codex to route through the gateway

```toml
# ~/.codex/config.toml
model_provider = "openai"

[openai]
base_url = "https://<gateway-alb-dns>/v1"
api_key  = "sk-<user-key>"
```

Test:

```bash
curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer sk-<user-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-oss-120b","messages":[{"role":"user","content":"OK?"}]}'
```

### 6. Confirm OTel traces land in CloudWatch

LiteLLM's `callbacks: ["otel"]` emits spans to the collector ALB on every
call. In the OTel collector log group (`/ecs/otel-collector`), search for
`otelcol.signal=traces` to confirm that spans are arriving.

### Local iteration

Use `docker compose up` under `deployment/litellm/` to start LiteLLM,
Postgres, and a debug OTel collector on localhost:4000. The compose file uses
the host EC2/Mac AWS credentials, so `aws configure` or an SSO profile is
required; there is no static AWS key material in the image or compose file.

### Teardown

RDS has `DeletionProtection: true` — disable it before deleting the stack,
otherwise `delete-stack` fails partway through:

```bash
DB_ID=$(aws cloudformation describe-stack-resources \
  --stack-name codex-litellm-gateway --region $REGION \
  --query "StackResources[?LogicalResourceId=='RDSInstance'].PhysicalResourceId" \
  --output text)

aws rds modify-db-instance \
  --db-instance-identifier $DB_ID \
  --no-deletion-protection --apply-immediately --region $REGION

aws cloudformation delete-stack \
  --stack-name codex-litellm-gateway --region $REGION

aws ecr delete-repository \
  --repository-name codex-litellm --force --region $REGION
```

## Also consider

All of these cover the pattern above; choose based on what your organization already operates.

| Gateway | One-line trade-off |
|---|---|
| **Portkey** | Hosted or self-hosted; strongest guardrails and prompt caching story; adds a vendor dependency. |
| **Bifrost** | Self-hosted Go-based gateway; low per-request overhead; smaller ecosystem than LiteLLM or Portkey. |
| **Kong AI Gateway** | Best if you already run Kong for non-AI traffic — reuses existing auth, rate-limit, and OTel plumbing. |
| **Helicone** | Lightweight proxy focused on observability; weaker on budget enforcement and JWT auth than LiteLLM or Portkey. |
| **AWS Bedrock Gateway sample** | AWS-owned reference implementation; minimal surface, but no built-in per-user budgets — you implement them yourself. |
| **Custom FastAPI shim** | Suitable if your needs are modest and you already have the operational capacity; you rebuild budgets, OTel, and SSO from scratch. |

## Known pitfalls

- **Cost floor.** ALB + RDS + ECS Fargate costs approximately $80–120/month even when idle. The
  IdC path has no comparable standing cost.
- **RDS deletion protection.** Enabled by default; teardown requires the
  `modify-db-instance` step above.
- **Region mismatch pitfall.** The template default `AwsRegion=us-east-1`
  must be overridden on every deployment.
- **`gpt-5.4` model alias.** Shipped in `litellm_config.yaml` as a
  placeholder; verify that it resolves before relying on it.
