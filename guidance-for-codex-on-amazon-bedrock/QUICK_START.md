# Quick Start — `cxwb` wizard

Guided wizard for all four deployment shapes this guidance supports:

| | **Deploy new** (stacks + bundle) | **BYO** (bundle only) |
|---|---|---|
| **IAM Identity Center** (recommended) | Creates the Bedrock role + policy stack and generates the developer bundle. | Assumes the role + permission set already exist; generates the developer bundle only. |
| **LiteLLM Gateway** (alternative) | Creates networking + OTel collector + LiteLLM gateway stacks and generates a bundle pointing at the new ALB. | Points at a gateway you already run (LiteLLM, Portkey, Kong AI, custom); generates a bundle pointing at that URL. |

IdC uses SigV4 over AWS SSO; Gateway uses a bearer key over HTTPS. Choose based on the criteria in [docs/01-decide.md](docs/01-decide.md).

## Install

```bash
cd source/
uv sync
uv run cxwb --help
```

Prerequisites: Python 3.10–3.13, [uv](https://docs.astral.sh/uv/getting-started/installation/), AWS CLI v2 authenticated to an account with the required permissions, and Bedrock activated in your target region.

## Flow

```bash
uv run cxwb init                  # pick path, answer prompts, save profile
uv run cxwb deploy --profile <n>  # create CloudFormation stacks
uv run cxwb status --profile <n>  # show stack states
uv run cxwb distribute --profile <n> --bucket my-bucket    # one bundle per deployment
uv run cxwb destroy --profile <n> # tear it all down
```

Profiles are saved to `~/.cxwb/profiles/<name>.json` as plain JSON, safe to inspect or edit manually.

## `cxwb init` prompts

### IAM Identity Center — deploy new

1. CloudFormation stack name (default `codex-bedrock-idc`).
2. IdC start URL (e.g. `https://d-xxxxxxxxxx.awsapps.com/start`).
3. IdC home region.
4. AWS account ID holding the Bedrock role.
5. Permission set name (default `CodexBedrockUser`).
6. Bedrock region.
7. Default Codex model (default `openai.gpt-5.4`).
8. Codex profile name written into `~/.codex/config.toml`.
9. Optional OTel endpoint.
10. Profile name.

`cxwb deploy` creates the Bedrock policy + role stack. Attach the customer-managed policy to your permission set in the IdC console, then run `cxwb distribute`.

### IAM Identity Center — existing (BYO)

For organizations that already run IdC with a Bedrock-invoke role trusted by `sso.amazonaws.com` and attached to a permission set. `cxwb` skips the stack and generates only the bundle.

Prompts: the same as above without the stack name. `cxwb deploy` is a no-op. `cxwb distribute` produces the developer bundle.

### LiteLLM Gateway path — deploy new

1. AWS region.
2. Networking / OTel / gateway stack names.
3. LiteLLM container image URI in ECR.
4. ALB ingress CIDR (default `10.0.0.0/16`).
5. Auto-generate master key + DB password, or enter your own.
6. Self-service key endpoint URL (optional).
7. Default model alias.
8. Profile name.

`cxwb deploy` creates networking → OTel collector → LiteLLM gateway in order. `cxwb distribute` generates one bundle for the deployment that directs developers to the gateway URL and the self-service key endpoint (LiteLLM SSO `/sso/key/generate` or equivalent). Developers generate their own keys at install time — bundles never contain credentials.

### Existing gateway (BYO)

Use this when a gateway is already running — LiteLLM, Portkey, Kong AI, Helicone, or a custom shim.

1. Gateway base URL (e.g. `https://gw.example.com/v1`).
2. Self-service key endpoint (optional).
3. Default model alias.
4. Region for S3 bundle upload.

`cxwb deploy` is a no-op; run `cxwb distribute` to produce the bundle and optionally presign an S3 URL.

## Scope

The wizard deploys the CloudFormation templates in `deployment/` and runs the bundle generators under `deployment/scripts/`. Profiles live in `~/.cxwb/profiles/<name>.json` with two boolean-like fields driving behavior:

- `auth`: `"idc"` or `"gateway"` — which bundle generator to run.
- `manages_infra`: `true` if `cxwb deploy` should create/destroy stacks, `false` if it should no-op (BYO).

It intentionally does not:

- Build signed installers or per-platform binaries.
- Deploy a Cognito user pool or an authenticated landing page.
- Manage Windows CodeBuild.
- Generate or rotate per-user gateway keys (developers self-serve via the gateway's SSO endpoint).
- Manage LiteLLM per-user budgets.

For anything beyond the standard path, refer to the manual docs: [docs/deploy-identity-center.md](docs/deploy-identity-center.md) and [QUICKSTART_PATTERN_GATEWAY.md](QUICKSTART_PATTERN_GATEWAY.md). The wizard and the manual path deploy the same templates.
