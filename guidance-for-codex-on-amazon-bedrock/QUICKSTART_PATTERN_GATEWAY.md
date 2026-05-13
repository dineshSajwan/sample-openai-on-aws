# Quick Start: Pattern 2 — Governed Gateway

Deploy Codex on Bedrock with LiteLLM gateway for hard quota enforcement and centralized policy control.

**Use this pattern if:**
- ✅ You need hard per-user/per-team budget limits (request blocking)
- ✅ You need rate limiting (RPM/TPM enforcement)
- ✅ You don't use IdC and don't want to set it up
- ✅ You need centralized model routing or automatic fallback

---

## Overview

**What You're Deploying:**
```
Corporate IdP (Okta/Azure) → OIDC → LiteLLM Gateway → Bedrock
                                        ↓
                               Hard quota enforcement
                               Rate limiting (RPM/TPM)
                               Model routing/fallback
```


**What Developers Get:**
- Self-service API key from gateway portal
- No AWS CLI or IdC required
- OpenAI-compatible API format

---

## Prerequisites

### Required

- [ ] AWS account with admin permissions (ECS, VPC, ALB, RDS, CloudFormation)
- [ ] Amazon Bedrock activated in target region (e.g., `us-west-2`)
- [ ] AWS credentials configured (one of):
  - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
  - Credentials file (`~/.aws/credentials`)
  - AWS SSO profile
- [ ] Python 3.10-3.13 + uv ([install uv](https://docs.astral.sh/uv/getting-started/installation/))
- [ ] Docker installed and running (for building LiteLLM container image)

### Optional (For OIDC Self-Service)

- [ ] Identity provider with OIDC support (Okta, Azure AD, Auth0, Cognito)
- [ ] JWKS URL from your IdP (e.g., `https://tenant.okta.com/.well-known/jwks.json`)

**Note:** OIDC self-service is now available via **custom JWT middleware** - no Enterprise license required! See [Option B: Self-Service OIDC](#option-b-self-service-oidc-portal-custom-jwt-middleware) for setup.

---

## Deployment Options

### Option A: Wizard (Recommended)

**Fastest deployment path:**

```bash
# 1. Clone repo
git clone https://github.com/aws-samples/guidance-for-codex-on-aws.git
cd guidance-for-codex-on-aws/guidance-for-codex-on-amazon-bedrock

# 2. Install CLI
cd source/
uv sync

# 3. Run wizard
uv run cxwb init

# Select: Gateway path
# Answer prompts:
# - Deployment path? → LiteLLM Gateway — deploy new
# - AWS region? → us-west-2
# - LiteLLM Docker image? → Build automatically (Recommended)
# - LiteLLM version? → v1.61.29 (Recommended)
# - Enable OIDC/SSO? → No (use admin keys) OR Yes (self-service)
#   
#   If Yes to OIDC:
#   - JWKS URL? → https://your-tenant.okta.com/.well-known/jwks.json
#   - JWT Audience? → (optional, your client ID)
#   - JWT Issuer? → (optional, your IdP URL)
#
# - LiteLLM master key? → (auto-generated)
# - Database password? → (auto-generated)
# - Allowed CIDR? → 10.0.0.0/8 (corporate network)
# - Default model? → openai.gpt-oss-safeguard-120b
# - Profile name? → codex-gateway

# 4. Build Docker images
# If OIDC enabled, build JWT middleware first:
uv run cxwb build-jwt --profile <profile-name>  # Only if OIDC enabled

# Build LiteLLM image:
uv run cxwb build --profile <profile-name>

# This:
# - Builds multi-arch Docker images (ARM64 + x86_64)
# - Creates ECR repositories
# - Pushes images to ECR
# - Updates profile with image URIs

# 5. Deploy infrastructure
uv run cxwb deploy --profile  <profile-name>

# This deploys stacks in order:
# 1. codex-otel-networking (VPC, subnets, NAT gateway)
# 2. codex-otel-collector (OpenTelemetry collector for metrics)
# 3. codex-user-key-mapping (DynamoDB table - if OIDC enabled)
# 4. codex-litellm-gateway (ECS Fargate + ALB + LiteLLM + JWT middleware)

# Wait 10-15 minutes for deployment
# Outputs:
# - GatewayEndpoint = http://<alb-url>/v1
# - If OIDC enabled: Self-service portal at http://<alb-url>/api/my-key

# 6. Generate developer bundle
uv run cxwb distribute --profile <profile-name> --bucket my-bucket

# Output: S3 presigned URL
```

**Bundle contents:**
```
codex-gateway-config/
├── install.sh              # Developer runs this
├── uninstall.sh            # Cleanup script
├── refresh-key.sh          # Optional: refresh expired API key
├── config.toml.snippet     # Codex config fragment
├── DEV-SETUP.md            # Developer instructions with gateway URL
└── env.template            # Template for OPENAI_API_KEY
```

---

---

## Developer Installation

**Developers receive the bundle and:**

```bash
# 1. Extract bundle
unzip codex-gateway-config.zip
cd codex-gateway-config/

# 2. Run installer
./install.sh

# This:
# - Appends managed blocks to ~/.codex/config.toml
# - Creates ~/.codex/gateway-env template
```

### Getting API Key - Two Options

Choose based on your organization's needs:

| Option | Setup Time | Cost | Best For |
|--------|-----------|------|----------|
| **Option A: Admin-Generated Keys** | 5 min | $0/month | Small teams, quick start, simple workflow |
| **Option B: OIDC Self-Service** | 1-2 hours | ~$6-10/month | Large teams, self-service, SSO integration |

---

#### Option A: Admin-Generated Key (Simplest)

```bash
# 1. Contact your platform team/admin
# 2. Request API key for Codex access
# 3. Admin generates key via LiteLLM UI:
#    - Logs into https://<gateway-url>/ui with master key
#    - Navigates to "API Keys" section
#    - Clicks "Create New Key"
#    - Fills in:
#        • Key Name: user-alice@company.com
#        • User ID: alice@company.com (optional)
#        • Max Budget: $50/month (optional)
#        • Models: gpt-4o, gpt-4o-mini (optional - leave blank for all)
#    - Shares key via secure channel (1Password, Vault, email)
#
# 4. Developer sets environment variable
export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx

# Add to shell profile for persistence:
echo 'export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx' >> ~/.zshrc  # macOS
echo 'export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx' >> ~/.bashrc # Linux

# 5. Restart your shell or source the profile
source ~/.zshrc  # macOS
source ~/.bashrc # Linux
```

**Key Management:**
- ✅ Keys do NOT expire by default (set once, use forever)
- ✅ Admin can optionally configure expiration when creating key
- ✅ Admin tracks usage per user via LiteLLM UI dashboard
- ✅ Admin can revoke keys when needed (employee leaves, compromised)

---

#### Option B: Self-Service OIDC Portal (Custom JWT Middleware)

**✅ NOW AVAILABLE** - Uses custom JWT middleware (no Enterprise license required!)

**Cost:** ~$6-10/month additional AWS costs vs ~$500-2000+/month for LiteLLM Enterprise

**Architecture:**
```
Developer → Corporate IdP (Okta/Azure AD) → JWT Token
         ↓
JWT Middleware (validates JWT, manages user→key mapping)
         ↓
LiteLLM Gateway → Bedrock
```

**Benefits:**
- ✅ Developers self-serve (no admin bottleneck)
- ✅ Keys automatically linked to user identity
- ✅ Uses your existing corporate SSO (Okta, Azure AD, Auth0)
- ✅ Auto-caching in DynamoDB (90-day TTL)
- ✅ Audit trail (who generated what, when)
- ✅ **No Enterprise license required**

---

##### Setup: Enable OIDC During Init

**Step 1: Configure OIDC in Profile**

```bash
cd guidance-for-codex-on-amazon-bedrock/source
uv run cxwb init

# Select: LiteLLM Gateway — deploy new
# When asked "Enable OIDC/SSO self-service?"
# → Choose "Yes - enable OIDC for self-service (requires IdP setup)"

# Provide your IdP details:
# - JWKS URL: https://your-tenant.okta.com/.well-known/jwks.json
# - JWT Audience: your-client-id (optional)
# - JWT Issuer: https://your-tenant.okta.com (optional)
```

**Step 2: Build JWT Middleware Image**

```bash
# Build and push JWT middleware Docker image to ECR
uv run cxwb build-jwt --profile <profile-name>

# This:
# - Builds image from deployment/litellm/jwt-middleware/
# - Creates ECR repository: codex-jwt-middleware
# - Pushes image to ECR
# - Updates profile with jwt_middleware_image_uri
```

**Step 3: Build LiteLLM Image (as usual)**

```bash
uv run cxwb build --profile <profile-name>
```

**Step 4: Deploy Infrastructure**

```bash
uv run cxwb deploy --profile <profile-name>

# This deploys (in order):
# 1. Networking stack (VPC, subnets)
# 2. OTel collector stack
# 3. DynamoDB table for user-key mapping
# 4. LiteLLM gateway with JWT middleware sidecar
#
# Output includes:
# GatewayEndpoint = http://<alb-url>/v1
# Self-service portal = http://<alb-url>/api/my-key
```

---

##### Developer Experience: 3 Ways to Use OIDC

**Method 1: Self-Service Portal (Browser)**

```bash
# Developer opens portal in browser
open https://<gateway-url>/api/my-key

# 1. Browser redirects to corporate IdP (Okta/Azure AD)
# 2. Developer signs in with SSO credentials (work email + password + MFA)
# 3. IdP redirects back with JWT token
# 4. Middleware validates JWT, creates/fetches API key for user
# 5. API key displayed - developer copies it
```

**Method 2: Programmatic API Call**

```bash
# Get JWT token from your IdP (method varies by provider)
# For Okta example:
JWT_TOKEN=$(curl -X POST https://your-tenant.okta.com/oauth2/v1/token \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=openid email profile" \
  | jq -r '.access_token')

# Call API to get key
curl https://<gateway-url>/api/my-key \
  -H "Authorization: Bearer $JWT_TOKEN"

# Response:
# {
#   "api_key": "sk-litellm-xxxxxxxxxxxxx",
#   "user_id": "user@company.com",
#   "email": "user@company.com"
# }
```

**Method 3: Direct Usage (Transparent)**

```bash
# Developers can use JWT tokens directly for API calls
# (middleware auto-creates key on first request)

export JWT_TOKEN="eyJhbGc..."

curl https://<gateway-url>/v1/chat/completions \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Middleware automatically:
# 1. Validates JWT signature and claims
# 2. Extracts user identity (sub, email)
# 3. Gets or creates API key for user (cached in DynamoDB)
# 4. Forwards to LiteLLM with API key
# 5. Streams response back
```

**Recommended for Most Users:** Method 1 (Self-Service Portal) - simple, visual, works for everyone.

---

##### After Getting Key: Set Environment Variable

```bash
# Set for current shell
export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx

# Add to shell profile for persistence:
echo 'export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx' >> ~/.zshrc  # macOS
echo 'export OPENAI_API_KEY=sk-litellm-xxxxxxxxxxxxx' >> ~/.bashrc # Linux

# Restart your shell or source the profile
source ~/.zshrc  # macOS
source ~/.bashrc # Linux
```

---

##### Key Management

**Caching:**
- User→key mappings cached in DynamoDB (90-day TTL)
- In-memory cache for JWT validation results
- First request: creates key + caches mapping (~200ms)
- Subsequent requests: cache hit (~20-50ms overhead)

**Revocation:**
- When user leaves company: disable in IdP → they can't authenticate
- Admin can manually revoke keys via LiteLLM UI if needed
- Keys automatically expire from cache after 90 days (re-generated on next use)

**Audit Trail:**
- All key creation logged to CloudWatch
- Includes: user_id, email, timestamp, source (jwt-middleware)
- Query logs: `aws logs tail /ecs/litellm --filter-pattern "Creating API key"`

---

##### Troubleshooting OIDC

**Issue: JWT validation fails**

Symptom: `{"error": "Invalid JWT token: ..."}`

Causes:
1. JWKS URL incorrect or unreachable
2. JWT expired
3. JWT audience/issuer mismatch
4. JWT signed with wrong key

Fix:
```bash
# Verify JWKS URL is accessible
curl https://your-tenant.okta.com/.well-known/jwks.json

# Decode JWT to inspect claims (use jwt.io in browser or jq)
echo "$JWT_TOKEN" | cut -d. -f2 | base64 -d | jq

# Check audience and issuer match ECS environment variables
aws ecs describe-task-definition --task-definition <task-def-arn> \
  --query 'taskDefinition.containerDefinitions[?name==`jwt-middleware`].environment'
```

**Issue: API key creation fails**

Symptom: `{"error": "Key management failed: ..."}`

Causes:
1. LITELLM_MASTER_KEY invalid
2. LiteLLM container not responding
3. Network connectivity issues

Fix:
```bash
# Check LiteLLM is healthy
curl http://localhost:4000/health/liveliness

# Verify master key in Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id codex-litellm-gateway/litellm-master-key \
  --region us-west-2

# Check container logs
aws logs tail /ecs/litellm --follow --region us-west-2
```

**Issue: DynamoDB access denied**

Symptom: `Failed to cache API key in DynamoDB: ...`

Cause: ECS task role missing DynamoDB permissions

Fix:
```bash
# Check task role has DynamoDB policy
aws iam list-attached-role-policies --role-name <task-role-name>

# Should include policy with dynamodb:PutItem, dynamodb:GetItem
# If missing, redeploy stack (CloudFormation will add it)
```

---

##### Monitoring OIDC Usage

**CloudWatch Logs:**
```bash
# View JWT middleware logs
aws logs tail /ecs/litellm --follow --region us-west-2 --filter-pattern "jwt-middleware"

# Common patterns:
# - "JWT validated for user" - successful authentication
# - "JWT validation failed" - invalid tokens
# - "Creating API key for user" - new key generation
# - "API key found in DynamoDB" - cache hit
```

**Metrics to Track:**
1. **Authentication success rate**: Valid vs invalid JWT tokens
2. **Key cache hit rate**: DynamoDB hits vs misses
3. **Key creation rate**: New keys per day
4. **Request latency**: Added latency from JWT validation (~20-50ms)

---

##### Cost Breakdown

**Additional AWS services (compared to admin-generated keys):**

| Service | Monthly Cost | Purpose |
|---------|-------------|---------|
| DynamoDB table | ~$1-5 | User→key mapping cache |
| ECS task (JWT middleware) | ~$5 | +0.25 vCPU, +512MB RAM |
| ECR storage | ~$0.01 | +100MB for middleware image |
| **Total** | **~$6-10/month** | vs. $500-2000+/month Enterprise |

**Break-even:** If you have more than 1-2 developers, OIDC self-service saves admin time and pays for itself.

---

##### Alternative: Upgrade to LiteLLM Enterprise

If you need advanced features not in custom middleware:

| Feature | Custom JWT Middleware | LiteLLM Enterprise |
|---------|----------------------|-------------------|
| **Cost** | ~$6-10/month | ~$500-2000+/month |
| **Setup** | 1-2 hours | 1 hour |
| **OIDC/SSO** | ✅ Basic | ✅ Advanced (roles, RBAC) |
| **Key Management** | ✅ Auto-generation | ✅ Advanced policies |
| **Rate Limiting** | Use LiteLLM OSS features | ✅ Per-user/team |
| **Model Routing** | Use LiteLLM OSS features | ✅ Advanced routing |
| **Support** | Self-support | Enterprise support |

**Recommendation:** Start with custom middleware, upgrade to Enterprise later if you need vendor support or advanced RBAC.

---

##### Learn More

**Detailed JWT Middleware Documentation:**
- Architecture: [deployment/litellm/jwt-middleware/README.md](../deployment/litellm/jwt-middleware/README.md)
- Configuration: Environment variables, DynamoDB setup, security
- IdP Setup Guides: Okta, Azure AD, Auth0 examples
- Advanced Topics: Redis caching, rate limiting, RBAC

### Using Codex CLI with Gateway

**The install script automatically creates a `codex-gateway` alias for you!**

#### Three Ways to Use Codex CLI

**Option 1: Using `codex-gateway` alias (⭐ Recommended)**

```bash
# One-shot commands
codex-gateway exec "Write a Python hello world function"
codex-gateway exec "Explain this file" @README.md

# Interactive mode
codex-gateway

# Chat mode
codex-gateway chat "How do I parse JSON in Python?"
```

**Option 2: Using `codex` with explicit flags**

```bash
# Useful if you don't have the alias or want full control
codex -c 'model_provider="litellm-gateway"' -c 'model="gpt-4o"' exec "your prompt"

# Interactive
codex -c 'model_provider="litellm-gateway"' -c 'model="gpt-4o"'
```

**Option 3: Plain `codex` ⚠️ DON'T USE THIS**

```bash
codex  # ❌ This connects to api.openai.com, NOT your gateway!
       # You'll see a sign-in prompt asking for OpenAI credentials
```

**How the alias works:**

```bash
# The codex-gateway alias is just a shortcut:
alias codex-gateway='codex -c model_provider="litellm-gateway" -c model="gpt-4o"'

# It tells Codex to:
# 1. Use custom provider "litellm-gateway" (from ~/.codex/config.toml)
# 2. Use model "gpt-4o" (mapped by gateway to Bedrock model)
# 3. Send requests to: http://<gateway-url>/v1
# 4. Include Authorization header with your API key
```

---

### Test Your Setup

After running `./install.sh`, test both access methods to verify they route through your gateway.

#### Test 1: Direct API Call (curl)

```bash
# Set API key
export OPENAI_API_KEY="sk-litellm-xxxxxxxxxxxxx"

# Test with curl
curl -X POST "http://<gateway-url>/v1/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "messages": [{"role": "user", "content": "What is 2+2? Answer in one word"}]
  }'

# Expected output:
# {
#   "id": "chatcmpl-...",
#   "choices": [{
#     "message": {
#       "content": "Four",
#       "role": "assistant"
#     }
#   }],
#   "usage": {"total_tokens": 73, ...}
# }
```

✅ **Success indicators:**
- Returns JSON with `choices[0].message.content`
- No errors about authentication
- Response time ~2-3 seconds

❌ **Common errors:**
- `401 Unauthorized` → API key is wrong or not set
- `Connection refused` → Gateway URL is wrong or gateway is down
- `timeout` → Gateway is not accessible from your network

#### Test 2: Codex CLI

```bash
# Reload shell to activate alias
source ~/.zshrc  # or ~/.bashrc

# Test with codex-gateway alias
codex-gateway exec "What is 2+2? Answer in one word"

# Expected output:
# OpenAI Codex v0.130.0
# --------
# model: gpt-4o
# provider: litellm-gateway
# --------
# user
# What is 2+2? Answer in one word
# codex
# Four
# tokens used
# 6,060
```

✅ **Success indicators:**
- Shows `provider: litellm-gateway` (NOT `openai`)
- Shows `model: gpt-4o`
- Returns answer without reconnecting errors
- Shows `tokens used` count

❌ **Common errors:**
```bash
# ERROR: Reconnecting... 1/5
# ERROR: 401 Unauthorized: No api key passed in
# → Your http_headers in config is missing or wrong
# → Run ./install.sh again or edit ~/.codex/config.toml

# ERROR: Not inside a trusted directory
# → Run from a git repository or use:
#   codex -c 'model_provider="litellm-gateway"' -c 'model="gpt-4o"' exec --skip-git-repo-check "test"

# Shows "provider: openai" instead of "litellm-gateway"
# → You forgot to use codex-gateway or the -c flags
# → Use: codex-gateway exec "test"
```

#### Test 3: Verify Both Methods Use Same Gateway

```bash
# Terminal 1: Watch gateway logs in real-time
aws logs tail /ecs/codex-litellm-gateway --follow --region us-west-2 --profile <your-profile>

# Terminal 2: Test Method 1 (curl)
curl -X POST "http://<gateway-url>/v1/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"test curl"}]}'

# Check logs → Should see: POST /v1/chat/completions HTTP/1.1 200 OK

# Terminal 2: Test Method 2 (Codex CLI)
codex-gateway exec "test codex"

# Check logs → Should see: POST /v1/responses HTTP/1.1 200 OK
```

✅ **Success:** Both requests appear in the same gateway logs with `200 OK` status

---

### Quick Reference

| What | Command | Where It Goes |
|------|---------|---------------|
| **curl** | `curl -H "Authorization: Bearer $OPENAI_API_KEY" ...` | → Gateway `/v1/chat/completions` ✅ |
| **codex-gateway** | `codex-gateway exec "..."` | → Gateway `/v1/responses` ✅ |
| **codex with flags** | `codex -c model_provider="litellm-gateway" ...` | → Gateway `/v1/responses` ✅ |
| **plain codex** ❌ | `codex` | → `api.openai.com` ❌ (NOT your gateway!) |

---

## API Key Expiration & Auto-Refresh

### Do API Keys Expire?

**By default: NO.** API keys are long-lived and do not expire unless configured by admin.

```bash
# Developer workflow:
# 1. Get key once from OIDC portal or admin
# 2. Add to ~/.zshrc or ~/.bashrc
# 3. Use for months/years without re-authenticating
# 4. No refresh needed - it just works
```

### Optional: Admin-Configured Expiration

Admins can optionally set key expiration when creating keys:

```bash
# Admin creates key with 90-day expiration
curl -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{
    "key_alias": "user-alice@company.com",
    "duration": "90d"  # Key expires after 90 days
  }'
```

**If your organization uses expiring keys**, developers will need to regenerate periodically:

```bash
# When key expires (get error: "API key expired or invalid")

# Option 1: Use bundled refresh script (easiest)
cd codex-gateway-config/
./refresh-key.sh
# Opens browser, prompts for new key, updates profile automatically

# Option 2: Manual refresh
open https://<gateway-url>/sso/key/generate
# Copy new key
export OPENAI_API_KEY=sk-litellm-new-xxxxxxxxxxxxx
# Edit ~/.zshrc or ~/.bashrc with new key
```

### Auto-Refresh Script (If Expiration Enabled)

If your admin configured expiring keys, here's a helper script to auto-refresh:

**Save as `~/.local/bin/refresh-codex-key.sh`:**

```bash
#!/bin/bash
# Auto-refresh Codex API key via OIDC portal
# Run this when you get "API key expired" errors

GATEWAY_URL="https://<gateway-url>"
PROFILE_FILE="$HOME/.zshrc"  # Change to .bashrc for Linux

echo "🔄 Refreshing Codex API key..."
echo "Opening OIDC portal in browser..."

# Open self-service portal
open "$GATEWAY_URL/sso/key/generate" 2>/dev/null || \
  xdg-open "$GATEWAY_URL/sso/key/generate" 2>/dev/null || \
  echo "Please open: $GATEWAY_URL/sso/key/generate"

echo ""
echo "After authenticating:"
echo "1. Copy the new API key from the portal"
echo "2. Paste it below (input hidden for security)"
echo ""

# Prompt for new key
read -s -p "New API key: " NEW_KEY
echo ""

if [[ ! $NEW_KEY =~ ^sk-litellm- ]]; then
    echo "❌ Invalid key format. Expected: sk-litellm-..."
    exit 1
fi

# Update shell profile
if grep -q "export OPENAI_API_KEY=" "$PROFILE_FILE"; then
    # Replace existing key
    sed -i.bak "s|export OPENAI_API_KEY=.*|export OPENAI_API_KEY=$NEW_KEY|g" "$PROFILE_FILE"
    echo "✅ Updated $PROFILE_FILE"
else
    # Append new key
    echo "export OPENAI_API_KEY=$NEW_KEY" >> "$PROFILE_FILE"
    echo "✅ Added to $PROFILE_FILE"
fi

# Export for current shell
export OPENAI_API_KEY=$NEW_KEY

echo "✅ API key refreshed!"
echo ""
echo "Test with: curl -X POST \"$GATEWAY_URL/v1/chat/completions\" \\"
echo "  -H \"Authorization: Bearer \$OPENAI_API_KEY\" \\"
echo "  -d '{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}'"
```

**Usage:**

```bash
# Make executable
chmod +x ~/.local/bin/refresh-codex-key.sh

# Run when key expires
refresh-codex-key.sh
```

### Alternative: Periodic Refresh via Cron (Advanced)

For fully automated refresh (requires headless OIDC flow - not standard):

```bash
# Add to crontab (runs every 85 days for 90-day keys)
# Note: This requires machine OIDC credentials, not typical for developer setups
0 0 */85 * * ~/.local/bin/refresh-codex-key.sh
```

**Warning:** This approach requires:
- Service account with OIDC credentials (not personal SSO)
- Headless OAuth2 flow (client credentials grant)
- Most enterprises won't support this for individual developers

### Recommended Approach

**For most organizations:**
1. **Don't set key expiration** - let keys be long-lived
2. **Revoke keys via IdP offboarding** - when employee leaves, their OIDC identity is disabled, admin can query and revoke their keys
3. **Developers set key once** - add to shell profile and forget about it

**If you must use expiring keys:**
- Set expiration to 365 days (annual refresh)
- Send email notification 7 days before expiry
- Developers run refresh script when needed

---

## Validation

### Test Gateway Health

```bash
# 1. Check gateway is responding
curl "$GATEWAY_URL/health"

# Expected: {"status":"healthy"}

# 2. Test OpenAI compatibility
curl "$GATEWAY_URL/v1/models" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Expected: List of configured models

# 3. Test Bedrock integration
curl "$GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai.gpt-5.4",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }'

# Expected: JSON response with completion
```

### Test Quota Enforcement

```bash
# 1. Create test key with low budget
curl -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "test-quota",
    "models": ["openai.gpt-5.4"],
    "max_budget": 0.10,
    "budget_duration": "1d"
  }'

# Save the returned key: TEST_KEY=sk-litellm-test-...

# 2. Make multiple requests until quota exceeded
for i in {1..20}; do
  curl "$GATEWAY_URL/v1/chat/completions" \
    -H "Authorization: Bearer $TEST_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "model": "openai.gpt-5.4",
      "messages": [{"role": "user", "content": "Test '$i'"}],
      "max_tokens": 100
    }'
  sleep 1
done

# Expected: Eventually returns 429 Too Many Requests
# {"error": {"message": "Budget exceeded for key test-quota"}}
```

### Test Codex Integration

```bash
# 1. Check Codex config
cat ~/.codex/config.toml | grep -A5 "model_provider"

# Expected:
# model_provider = "openai"
# model = "openai.gpt-5.4"
# [openai]
# base_url = "https://<gateway-url>/v1"

# 2. Test Codex prompt
echo "Create a hello world function in Python" | codex

# Expected: Codex generates code via gateway
```

---

## Configure Quota Policies

### Per-User Budgets

```bash
# Create user-specific key
curl -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "user-alice@company.com",
    "user_id": "alice@company.com",
    "models": ["openai.gpt-5.4"],
    "max_budget": 50.0,
    "budget_duration": "30d",
    "metadata": {"department": "engineering", "team": "frontend"}
  }'
```

### Per-Team Budgets

```bash
# Create team key with higher limits
curl -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "team-platform",
    "team_id": "platform-team",
    "models": ["openai.gpt-5.4", "openai.gpt-oss-120b"],
    "max_budget": 500.0,
    "budget_duration": "30d",
    "tpm_limit": 100000,
    "rpm_limit": 1000,
    "metadata": {"cost_center": "CC-1234"}
  }'
```

### Rate Limits

```bash
# Set aggressive rate limits for new users
curl -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key_alias": "new-user-trial",
    "max_budget": 10.0,
    "budget_duration": "7d",
    "tpm_limit": 10000,
    "rpm_limit": 100,
    "duration": "7d"
  }'
```

### Model Routing

```bash
# Configure fallback model
curl -X POST "$GATEWAY_URL/model/new" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "openai.gpt-5.4",
    "litellm_params": {
      "model": "bedrock/openai.gpt-5.4",
      "aws_region_name": "us-west-2",
      "fallbacks": [
        {"model": "bedrock/openai.gpt-oss-120b"}
      ]
    }
  }'
```

---

## Optional: Add Monitoring (OTel)

**Deploy CloudWatch observability for usage tracking:**

```bash
cd deployment/scripts/

./deploy-otel-stack.sh \
  --region us-west-2 \
  --profile codex-gateway

# This deploys:
# - codex-otel-collector (ECS Fargate + ALB)
# - codex-otel-dashboard (CloudWatch dashboard)

# Get OTel collector URL
OTEL_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name codex-otel-collector \
  --region us-west-2 \
  --query 'Stacks[0].Outputs[?OutputKey==`CollectorURL`].OutputValue' \
  --output text)

# Configure LiteLLM to export metrics
curl -X POST "$GATEWAY_URL/config/update" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"success_callback\": [\"otel\"],
    \"otel_endpoint\": \"$OTEL_ENDPOINT\"
  }"

# View dashboard
open "https://console.aws.amazon.com/cloudwatch/home?region=us-west-2#dashboards:name=CodexOnBedrock"
```

---

## Troubleshooting

### Issue: Gateway returns 500 "Database connection failed"

**Cause:** RDS database not accessible from ECS tasks

**Fix:**
```bash
# Check security group allows ECS → RDS traffic
aws ec2 describe-security-groups \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=codex-gateway" \
  --query 'SecurityGroups[*].[GroupId,GroupName]'

# Verify RDS endpoint resolves
nslookup <rds-endpoint>

# Check ECS task logs
aws logs tail /ecs/codex-gateway --follow
```

### Issue: Gateway returns 403 "AccessDeniedException" when calling Bedrock

**Cause:** ECS task role missing Bedrock permissions

**Fix:**
```bash
# Get task role ARN
TASK_ROLE=$(aws cloudformation describe-stacks \
  --stack-name codex-gateway \
  --query 'Stacks[0].Outputs[?OutputKey==`TaskRoleArn`].OutputValue' \
  --output text)

# Verify policy attached
aws iam list-attached-role-policies --role-name <role-name>

# Manually attach if missing
aws iam attach-role-policy \
  --role-name <role-name> \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
```

### Issue: Self-service key generation fails with OIDC error

**Cause:** OIDC redirect URI mismatch

**Fix:**
1. Check IdP application settings
2. Verify redirect URI: `https://<gateway-url>/sso/callback`
3. Update CloudFormation parameter `OIDCRedirectURI` if ALB URL changed

### Issue 4: Docker Not Running During Build

**Symptom:**
```bash
uv run cxwb build --profile <profile-name>
# Error: failed to connect to docker API
```

**Cause:** Docker Desktop not running

**Fix:** Open Docker Desktop, wait for it to start, verify with `docker ps`, retry build

### Issue 5: ALB Connection Refused / Listener Deleted by AWS

**Symptom:** `curl: (7) Failed to connect` or connection timeout

**Cause:** AWS security scan auto-deleted publicly accessible ALB listener (`0.0.0.0/0`)

**Fix:** Restrict to your IP or corporate CIDR, then redeploy:
```bash
# Get your IP
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Update profile
cd ~/.cxwb/profiles
jq --arg ip "$MY_IP/32" '.allowed_cidr = $ip' <profile>.json > tmp.json && mv tmp.json <profile>.json

# Redeploy
cd guidance-for-codex-on-amazon-bedrock/source
uv run cxwb destroy --profile <profile> --yes
uv run cxwb deploy --profile <profile>
```

### Issue 6: Model Identifier Invalid

**Symptom:** `BedrockException - model identifier is invalid`

**Cause:** LiteLLM config uses wrong Bedrock model ID

**Fix:**
```bash
# Check available models
aws bedrock list-foundation-models --region us-west-2 \
  --query 'modelSummaries[?contains(modelId,`openai`)].{ModelId:modelId,Name:modelName}'

# Update deployment/litellm/litellm_config.yaml with correct IDs
# Rebuild and redeploy
uv run cxwb build && uv run cxwb deploy
```

### Issue 7: Authentication Error - Malformed API Key

**Symptom:** `Malformed API Key - Ensure Key has Bearer prefix`

**Cause:** Typo in environment variable - `OPEN_API_KEY` instead of `OPENAI_API_KEY`

**Fix:** `export OPENAI_API_KEY="sk-..."` (correct spelling)

### Issue 8: ECS Tasks Crash - "exec format error"

**Symptom:** Tasks start then immediately stop

**Cause:** Image built for wrong architecture (ARM vs x86)

**Fix:** Rebuild with multi-arch (default): `uv run cxwb build --profile <profile>`

### Issue 9: IP Changed, Gateway Unreachable

**Symptom:** Was working, now connection refused

**Cause:** Your IP changed, security group has old IP

**Fix:** Update security group or redeploy with new IP (see Issue 5)

### Issue 10: OIDC JWT Validation Fails

**Symptom:** Self-service portal or API call returns `{"error": "Invalid JWT token: ..."}`

**Cause:** JWT validation failed - could be JWKS URL unreachable, expired token, or claim mismatch

**Fix:**
```bash
# 1. Verify JWKS URL is accessible from ECS tasks
curl https://your-tenant.okta.com/.well-known/jwks.json

# 2. Decode JWT to inspect claims (use jwt.io or command line)
echo "$JWT_TOKEN" | cut -d. -f2 | base64 -d | jq

# Required claims:
# - sub (user ID) - REQUIRED
# - email (user email) - optional but recommended
# - groups (array) - optional

# 3. Check JWT middleware environment variables match IdP
aws ecs describe-task-definition \
  --task-definition codex-litellm-gateway-task \
  --query 'taskDefinition.containerDefinitions[?name==`jwt-middleware`].environment' \
  --region us-west-2

# Should show:
# - JWKS_URL: your IdP's JWKS endpoint
# - JWT_AUDIENCE: (if set, must match token's "aud" claim)
# - JWT_ISSUER: (if set, must match token's "iss" claim)

# 4. Check JWT middleware logs
aws logs tail /ecs/litellm --follow --region us-west-2 --filter-pattern "jwt-middleware"

# 5. Test JWT middleware directly
curl https://<gateway-url>/api/my-key \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -v

# If JWT is valid but key creation fails, check LiteLLM master key in Secrets Manager
```

### General Debugging Tips

**Network Access Issues:**
- Enterprise customers should use corporate network CIDR, not `0.0.0.0/0`
- AWS security scans auto-delete public listeners without WAF
- Update `AllowedCidr` in profile to corporate VPN range: `10.0.0.0/8`, `172.16.0.0/12`

**Multi-Architecture Docker Builds:**
- Default: builds for both ARM64 and x86_64 (works on all platforms)
- Single-arch: use `--no-multi-arch` flag for faster builds
- Cross-compilation: ARM Mac → x86 ECS uses QEMU (slower but works)

**Checking Service Health:**
```bash
# ECS service status
aws ecs describe-services --cluster codex-litellm-gateway-cluster \
  --services <service-name> --region us-west-2

# ALB target health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# CloudWatch logs
aws logs tail /ecs/litellm --follow --region us-west-2

# CloudFormation events
aws cloudformation describe-stack-events --stack-name codex-litellm-gateway \
  --region us-west-2 --max-items 10
```

---

## Cleanup

```bash
# 1. Delete CloudFormation stacks (in reverse order)
aws cloudformation delete-stack --stack-name codex-gateway --region us-west-2
aws cloudformation delete-stack --stack-name codex-gateway-db --region us-west-2
aws cloudformation delete-stack --stack-name codex-networking --region us-west-2

# 2. Delete ECR repository
aws ecr delete-repository --repository-name codex-litellm --force --region us-west-2

# 3. Developers uninstall
./uninstall.sh
```

---

---

## Next Steps

- **Configure quota policies:** [Configure Quota Policies](#configure-quota-policies)
- **Add monitoring:** [Optional: Add Monitoring](#optional-add-monitoring-otel)
- **Upgrade to Pattern 3:** [QUICKSTART_PATTERN_HYBRID.md](QUICKSTART_PATTERN_HYBRID.md)
- **Scale horizontally:** Add ECS task auto-scaling based on ALB metrics

---

## Support

- **Documentation:** [README.md](README.md)
- **Issues:** [GitHub Issues](https://github.com/aws-samples/guidance-for-codex-on-aws/issues)
- **Technical guide:** [docs/deploy-gateway.md](docs/deploy-gateway.md)
- **LiteLLM docs:** [docs.litellm.ai](https://docs.litellm.ai)
