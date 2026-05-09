# Guidance for Codex on Amazon Bedrock

Run [OpenAI Codex](https://openai.com/codex) against [Amazon Bedrock](https://aws.amazon.com/bedrock/)
(`openai.gpt-5.4`, `openai.gpt-oss-*`) with enterprise-grade identity, cost
attribution, and observability — without standing up any custom auth service.

**Who this is for:** AWS administrators and technical decision-makers
evaluating how to roll Codex out to developers at company scale.

**What you get:**
- Per-developer SSO sign-in (no shared keys, no static credentials).
- Per-user cost attribution in CloudTrail + Cost and Usage Reports.
- Optional CloudWatch usage dashboard (tokens, latency, spend by user).
- A signed, MDM-friendly developer bundle — install, `aws sso login`, done.

---

## Pick your path in 60 seconds

> **Decision rule:** If you can run IAM Identity Center, use IAM Identity Center.
> If you can't — or you need hard per-user budgets — run the Gateway.

| | **IAM Identity Center** _(recommended)_ | **Gateway** _(alternative)_ |
|---|---|---|
| Best for | Any org already using IdC / AWS SSO | Orgs that need hard per-user budgets |
| Dev setup | `aws sso login` | OIDC JWT + `OPENAI_BASE_URL` |
| Infra to run | **None** (free AWS control plane) | ECS Fargate + ALB + Postgres |
| Bedrock auth | Per-user federated IAM | Shared gateway task role |
| Per-user attribution | CloudTrail `userIdentity` (native) | JWT claim → OTel header |
| Hard per-user budgets | No (soft via quotas) | Yes |
| Codex provider | Native `amazon-bedrock` | Generic `openai` |
| Time to first call | ~5 min + dev SSO sign-in | ~15 min + gateway bring-up |

Full prereq checklists and comparison: **[docs/01-decide.md](docs/01-decide.md)**.

---

## Fastest path — the `cxwb` wizard

Guided wizard for all four deployment shapes this guide supports:

| | Deploy stacks | Bundle only (BYO) |
|---|---|---|
| **IdC auth** | IdC stack + bundle | Bundle for existing IdC role |
| **Gateway auth** | LiteLLM stacks + bundle | Bundle for existing gateway |

```bash
cd source/ && poetry install
poetry run cxwb init                        # pick one of the four, answer prompts
poetry run cxwb deploy --profile default    # deploys stacks if the profile owns them
poetry run cxwb distribute --profile default --bucket <bucket>   # one bundle per deployment
```

Full walkthrough: **[QUICK_START.md](QUICK_START.md)**. The manual steps below deploy the same CloudFormation templates — use them when you want to customize a template, plug into existing IaC, or debug a failed stack.

---

## Quick start — IAM Identity Center path (manual)

### 1. Deploy the Bedrock auth stack (admin, once)

```bash
aws cloudformation deploy \
  --stack-name codex-bedrock-idc \
  --template-file deployment/infrastructure/bedrock-auth-idc.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-west-2
```

Creates a customer-managed Bedrock policy + an IAM role trusted by
`sso.amazonaws.com` and scoped to `AWSReservedSSO_CodexBedrockUser_*` sessions.

### 2. Wire it to a permission set (admin, once)

In IAM Identity Center, create a permission set named `CodexBedrockUser`,
attach the customer-managed policy from step 1, and assign it to your Codex
developer group.

### 3. Generate the developer bundle (admin)

```bash
deployment/scripts/generate-codex-sso-config.sh \
  --start-url https://d-xxxxxxxxxx.awsapps.com/start \
  --sso-region us-east-1 \
  --account-id 123456789012 \
  --permission-set CodexBedrockUser \
  --bedrock-region us-west-2 \
  --profile-name codex \
  --outdir ./dist/codex-sso
```

Distribute `./dist/codex-sso/` via zip + S3 presigned URL, MDM, or your
package manager of choice.

### 4. Install on developer machines

```bash
./install.sh                      # writes fenced managed blocks to
                                  # ~/.aws/config and ~/.codex/config.toml
aws sso login --profile codex
codex                             # uses native amazon-bedrock provider
```

`./uninstall.sh` cleanly removes every change on request.

Full walkthrough (validation, OTel add-on, failure modes, teardown):
**[docs/deploy-identity-center.md](docs/deploy-identity-center.md)**.

---

## How identity flows end-to-end

The invariant every path preserves: **the SSO user identity reaches
CloudTrail and CUR**, so cost and audit queries are per-developer by default.

```
Corporate IdP  ──(SAML+SCIM)──▶  AWS IAM Identity Center
                                        │
                                        ▼
                         AWSReservedSSO_CodexBedrockUser_* session
                                        │
                                        ▼
                           Bedrock customer-managed policy
                                        │
                   ┌────────────────────┼────────────────────┐
                   ▼                    ▼                    ▼
           CloudTrail            Bedrock Converse     CloudWatch (OTel)
        userIdentity = UPN      (native SigV4 path)   user.id = UPN header
                   │
                   ▼
              CUR (cost)
```

---

## Supported models

| Model ID | Notes |
|---|---|
| `openai.gpt-5.4` | **Recommended default.** Served via Bedrock Mantle. |
| `openai.gpt-oss-120b` | GPT-OSS 120B (Converse-compatible). |
| `openai.gpt-oss-20b` | GPT-OSS 20B (Converse-compatible). |

Available in `us-east-1`, `us-east-2`, `us-west-2`. Full region × model
matrix: **[docs/reference-regions.md](docs/reference-regions.md)**.

---

## Documentation map

| If you want to… | Read |
|---|---|
| Run the guided `cxwb` wizard | [QUICK_START.md](QUICK_START.md) |
| Choose a deployment path | [docs/01-decide.md](docs/01-decide.md) |
| Deploy the recommended path | [docs/deploy-identity-center.md](docs/deploy-identity-center.md) |
| Deploy the gateway alternative | [docs/deploy-gateway.md](docs/deploy-gateway.md) |
| Set up monitoring + cost attribution | [docs/operate-monitoring.md](docs/operate-monitoring.md) |
| Diagnose a failure | [docs/operate-troubleshooting.md](docs/operate-troubleshooting.md) |
| Check region / model support | [docs/reference-regions.md](docs/reference-regions.md) |

## Repo layout

```
guidance-for-codex-on-amazon-bedrock/
├── README.md                              ← you are here
├── docs/                                  ← decide / deploy / operate / reference
├── deployment/
│   ├── infrastructure/                    ← CloudFormation templates
│   │   ├── bedrock-auth-idc.yaml          ← IdC Bedrock policy + role
│   │   ├── networking.yaml                ← VPC for the OTel stack
│   │   ├── otel-collector.yaml            ← ECS Fargate OTel collector
│   │   └── codex-otel-dashboard.yaml      ← CloudWatch usage dashboard
│   ├── litellm/                           ← LiteLLM gateway reference impl
│   └── scripts/
│       ├── generate-codex-sso-config.sh   ← dev-bundle generator
│       └── deploy-otel-stack.sh           ← OTel one-shot deploy
└── assets/images/                         ← architecture + dashboard images
```

---

## License

MIT — see [LICENSE](LICENSE).
