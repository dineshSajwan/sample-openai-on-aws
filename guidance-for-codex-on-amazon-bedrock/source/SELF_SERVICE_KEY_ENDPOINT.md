# Self-Service Key Endpoint Explanation

## What It Is

The **self-service key endpoint** is a web interface hosted by LiteLLM Gateway that allows developers to generate their own API keys without admin intervention.

**URL format:** `https://<gateway-url>/sso/key/generate`

**Example:** `https://codex-alb-123456.us-west-2.elb.amazonaws.com/sso/key/generate`

## How It Works

### Visual Flow

```
Developer                    SSO Provider           LiteLLM Gateway
┌──────────┐                ┌────────────┐         ┌─────────────┐
│          │   1. Visit URL │            │         │             │
│ Browser  │───────────────────────────────────────▶│ /sso/key/   │
│          │                │            │         │ generate    │
│          │                │            │         │             │
│          │   2. Redirect  │            │         │             │
│          │◀───────────────────────────────────────│             │
│          │                │            │         │             │
│          │   3. Login     │            │         │             │
│          │───────────────▶│ Okta/Azure │         │             │
│          │                │ AD/Auth0   │         │             │
│          │   4. Token     │            │         │             │
│          │◀───────────────│            │         │             │
│          │                │            │         │             │
│          │   5. Token     │            │         │             │
│          │───────────────────────────────────────▶│ Verify JWT  │
│          │                │            │         │ Create key  │
│          │                │            │         │ in DB       │
│          │   6. API Key   │            │         │             │
│          │◀───────────────────────────────────────│ Return key  │
│          │   sk-abc123... │            │         │             │
└──────────┘                └────────────┘         └─────────────┘
     │
     │  7. Use key
     ▼
┌──────────────────────────┐
│ codex CLI                │
│ OPENAI_API_KEY=sk-abc... │
└──────────────────────────┘
```

### Step-by-Step

1. **Developer opens URL** in browser: `https://gateway-url/sso/key/generate`
2. **Gateway redirects** to SSO provider (Okta/Azure AD/etc)
3. **Developer logs in** with corporate credentials (email + password + MFA)
4. **SSO returns token** to gateway with user identity
5. **Gateway generates key** and stores in database:
   ```sql
   INSERT INTO virtual_keys (key_hash, user_id, created_at)
   VALUES ('hash(sk-abc...)', 'jane@company.com', NOW());
   ```
6. **Gateway displays key** on web page: `sk-1234567890abcdef...`
7. **Developer copies key** and uses it in their environment

## In cxwb init

When `cxwb init` asks for this field:

```
Self-service key endpoint (optional, e.g. https://gw/sso/key/generate):
```

### Option 1: Provide URL (Enable Self-Service)

**Input:**
```
https://codex-alb-123456.us-west-2.elb.amazonaws.com/sso/key/generate
```

**What happens:**
- `cxwb distribute` generates a developer bundle
- Bundle includes `DEV-SETUP.md` with self-service instructions:

```markdown
## 1. Get a per-user key

Self-service via IdP SSO:

```bash
open "https://codex-alb-123456.us-west-2.elb.amazonaws.com/sso/key/generate"
# Copy the sk-... key the page returns, then:
export OPENAI_API_KEY="sk-..."
```

## 2. Install

```bash
./install.sh
export OPENAI_API_KEY="sk-..."   # add to ~/.zshrc / ~/.bashrc
codex
```
```

**Developer experience:**
- Downloads bundle
- Opens URL in browser
- Logs in with SSO
- Gets key instantly
- Runs install script
- **Total time: 2 minutes**

### Option 2: Leave Blank (Admin-Generated Keys)

**Input:**
```
[Press Enter - leave empty]
```

**What happens:**
- `cxwb distribute` generates bundle
- Bundle includes `DEV-SETUP.md` with manual instructions:

```markdown
## 1. Get a per-user key

Ask your platform team for a per-user key.

## 2. Install

```bash
./install.sh
export OPENAI_API_KEY="sk-..."   # add to ~/.zshrc / ~/.bashrc
codex
```
```

**Developer experience:**
- Downloads bundle
- **Contacts admin** (Slack/email/ticket)
- **Waits for response** (hours to days)
- Admin generates key via API
- Admin sends key (need secure channel)
- Runs install script
- **Total time: hours to days**

## Two Key Distribution Models

### Model 1: Self-Service (Recommended for 10+ developers)

```
Developer Flow:
  Visit URL → SSO login → Copy key → Done
  
Admin Effort:
  One-time OIDC setup → Zero ongoing work

Pros:
  ✓ Instant onboarding (2 minutes)
  ✓ No admin bottleneck
  ✓ Keys tied to SSO identity
  ✓ Automatic audit trail (who generated when)
  ✓ Developer autonomy

Cons:
  ✗ Requires OIDC configuration
  ✗ Gateway must be accessible (public or VPN)
  ✗ Requires LiteLLM UI feature (open-source has it)

Best for:
  - Teams with existing SSO (Okta/Azure AD)
  - 10+ developers
  - Frequent onboarding/offboarding
```

### Model 2: Admin-Generated (Simpler for small teams)

```
Developer Flow:
  Ask admin → Wait → Receive key → Done

Admin Effort:
  Per-developer API call or UI click

Pros:
  ✓ No OIDC setup required
  ✓ Works with private gateway (no public URL)
  ✓ Full admin control
  ✓ Can work with any auth system

Cons:
  ✗ Admin becomes bottleneck
  ✗ Slower onboarding (hours to days)
  ✗ Need secure key distribution (not email/Slack)
  ✗ Manual work per developer

Best for:
  - Small teams (<10 developers)
  - Infrequent onboarding
  - No existing SSO system
  - Private gateway (no internet access)
```

## Admin Key Generation (Model 2)

If you choose admin-generated keys, the admin creates keys using:

### Option A: LiteLLM API

```bash
# Admin generates key for a developer
curl -X POST https://gateway-url/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "jane@company.com",
    "max_budget": 100.0,
    "duration": "30d",
    "models": ["openai.gpt-5.4", "gpt-4o"],
    "metadata": {
      "team": "ml-platform",
      "cost_center": "engineering"
    }
  }'

# Response:
{
  "key": "sk-1234567890abcdef...",
  "expires": "2025-06-11T00:00:00Z"
}
```

### Option B: LiteLLM Admin UI

1. Visit: `https://gateway-url/ui`
2. Login with master key
3. Navigate to: **Keys** → **Create Key**
4. Fill form:
   - User ID: `jane@company.com`
   - Max Budget: `$100`
   - Duration: `30 days`
5. Click **Generate**
6. Copy key and send to developer securely

### Secure Key Distribution

**❌ DON'T:**
- Email the key (plaintext, logged, cached)
- Slack/Teams message (searchable, stored)
- Shared document (accessible to others)

**✅ DO:**
- Password manager (1Password shared vault)
- Encrypted messaging (Signal with disappearing messages)
- In-person handoff (show on screen, don't send)
- Temporary secure link (e.g., OneTimeSecret.com)
- Internal secrets management tool (HashiCorp Vault, AWS Secrets Manager)

## Prerequisites for Self-Service

### 1. OIDC Provider Configuration

Create an OIDC application in your IdP:

**Okta:**
- Applications → Create App Integration
- Sign-in method: OIDC
- Application type: Web Application
- Sign-in redirect URI: `https://gateway-url/sso/callback`
- Sign-out redirect URI: `https://gateway-url`
- Assignments: All employees (or specific group)

**Azure AD:**
- App registrations → New registration
- Redirect URI: `https://gateway-url/sso/callback` (Web)
- Certificates & secrets → New client secret
- API permissions → Add Microsoft Graph (openid, profile, email)

**Auth0:**
- Applications → Create Application
- Application type: Regular Web Application
- Allowed Callback URLs: `https://gateway-url/sso/callback`
- Allowed Logout URLs: `https://gateway-url`

### 2. LiteLLM Configuration

Update `deployment/litellm/litellm_config.yaml`:

```yaml
general_settings:
  # Enable UI (includes self-service portal)
  ui_logo_path: "https://your-company.com/logo.png"  # Optional
  
  # SSO configuration (if using OIDC login for UI itself)
  # This is DIFFERENT from enable_jwt_auth - this is for the UI login
  litellm_ui_sso:
    provider: "okta"  # or "azure", "auth0", "cognito"
    client_id: "os.environ/OIDC_CLIENT_ID"
    client_secret: "os.environ/OIDC_CLIENT_SECRET"
    authorization_endpoint: "https://company.okta.com/oauth2/default/v1/authorize"
    token_endpoint: "https://company.okta.com/oauth2/default/v1/token"
```

### 3. Environment Variables

Set in ECS task definition:

```yaml
Environment:
  - Name: LITELLM_MASTER_KEY
    Value: sk-master-key-here
  - Name: OIDC_CLIENT_ID
    Value: your-oidc-client-id
  - Name: OIDC_CLIENT_SECRET
    Value: your-oidc-client-secret
```

## URL Construction

The self-service key endpoint URL is constructed as:

```
<gateway-url-base>/sso/key/generate
```

**Examples:**

| Gateway Base URL | Self-Service Key URL |
|------------------|----------------------|
| `https://codex-alb-123456.us-west-2.elb.amazonaws.com` | `https://codex-alb-123456.us-west-2.elb.amazonaws.com/sso/key/generate` |
| `https://codex.company.internal` | `https://codex.company.internal/sso/key/generate` |
| `https://ai-gateway.example.com/v1` | `https://ai-gateway.example.com/sso/key/generate` (note: no /v1) |

**Important:** The `/sso/key/generate` path is for the **UI**, not the **API**. Don't include `/v1` in this URL.

## Testing Self-Service Setup

After deployment:

1. **Open URL in browser:**
   ```bash
   open https://your-gateway-url/sso/key/generate
   ```

2. **Expected behavior:**
   - Redirects to SSO login (Okta/Azure AD)
   - After login, shows key generation page
   - Click "Generate Key" → displays `sk-...` key

3. **Test the key:**
   ```bash
   export OPENAI_API_KEY="sk-..."
   curl https://your-gateway-url/v1/chat/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $OPENAI_API_KEY" \
     -d '{
       "model": "openai.gpt-5.4",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
   ```

## Troubleshooting

### "404 Not Found" when visiting URL

**Cause:** UI is not enabled or gateway not deployed correctly

**Fix:**
1. Check LiteLLM is running: `curl https://gateway-url/health`
2. Verify UI is enabled in config (should be by default)
3. Check ECS task logs for errors

### Redirects to SSO but gets "invalid_redirect_uri"

**Cause:** OIDC app redirect URI doesn't match

**Fix:**
1. Check OIDC app config in IdP
2. Ensure redirect URI is exactly: `https://gateway-url/sso/callback`
3. No trailing slash, must be HTTPS

### Login succeeds but "Unauthorized"

**Cause:** OIDC credentials not configured in LiteLLM

**Fix:**
1. Verify `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` env vars are set
2. Check they match IdP application credentials
3. Restart ECS task to pick up new env vars

### Key generated but doesn't work

**Cause:** Key not saved to database, or database connection issue

**Fix:**
1. Check RDS is running and accessible
2. Verify `DATABASE_URL` env var is correct
3. Check ECS task logs for database errors
4. Verify security group allows ECS → RDS on port 5432

## Summary

**Self-service key endpoint = web UI for developers to generate their own API keys**

| Aspect | Details |
|--------|---------|
| **URL** | `https://gateway-url/sso/key/generate` |
| **Auth** | Corporate SSO (Okta/Azure AD/Auth0) |
| **Result** | Developer gets `sk-...` API key instantly |
| **When to use** | 10+ developers, have SSO, want fast onboarding |
| **When to skip** | Small team, no SSO, want admin control |
| **Setup time** | 1-2 hours (OIDC config) |
| **Ongoing work** | Zero (fully self-service) |

**In `cxwb init`:**
- **Provide URL** → Developer bundle includes self-service instructions
- **Leave blank** → Developer bundle says "Ask admin for key"
