# OIDC/JWT Authentication in LiteLLM Gateway

## Overview

LiteLLM gateway supports two authentication modes:

1. **API Keys** (open-source, currently configured)
2. **OIDC/JWT** (Enterprise feature, commented out in config)

## Authentication Modes Comparison

| Feature | API Keys | OIDC/JWT |
|---------|----------|----------|
| **Open-source support** | ✅ Yes | ❌ No (Enterprise only) |
| **Identity provider** | LiteLLM internal DB | Corporate SSO (Okta/Azure AD) |
| **Key management** | Manual (create/rotate/revoke) | Automatic (IdP handles) |
| **User onboarding** | Admin creates key per user | Automatic with SSO login |
| **User offboarding** | Manual key revocation | Auto-revoked when disabled in IdP |
| **Team mapping** | Manual assignment | Automatic from OIDC groups claim |
| **Token lifetime** | Permanent (until revoked) | Short-lived (15min-1hr, refreshable) |
| **Cost** | Free | Requires LiteLLM Enterprise license |

## Current Configuration: API Keys

**File:** `deployment/litellm/litellm_config.yaml`

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY  # Admin key
  # User keys stored in RDS Postgres database
```

**How it works:**

1. **Admin creates keys** (via LiteLLM API or UI):
   ```bash
   curl -X POST https://gateway/key/generate \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     -d '{
       "user_id": "developer@company.com",
       "max_budget": 100.0,
       "duration": "30d"
     }'
   # Response: {"key": "sk-1234567890abcdef"}
   ```

2. **Developer uses key**:
   ```bash
   export OPENAI_API_KEY="sk-1234567890abcdef"
   codex -c "explain this code" --file app.py
   ```

3. **Gateway validates**:
   - Query: `SELECT * FROM virtual_keys WHERE key_hash = hash('sk-1234...')`
   - Check quota, rate limits
   - Use gateway's IAM role to call Bedrock
   - Track spend in `spend_tracking` table

**Database schema:**
```sql
virtual_keys (
  key_hash TEXT PRIMARY KEY,
  user_id TEXT,
  team_id TEXT,
  max_budget REAL,
  spend REAL,
  created_at TIMESTAMP,
  expires_at TIMESTAMP
)

spend_tracking (
  request_id TEXT PRIMARY KEY,
  key_hash TEXT,
  model TEXT,
  input_tokens INT,
  output_tokens INT,
  cost REAL,
  timestamp TIMESTAMP
)
```

## OIDC/JWT Mode (Enterprise)

**File:** `deployment/litellm/litellm_config.yaml` (currently commented out)

```yaml
general_settings:
  enable_jwt_auth: true
  litellm_jwtauth:
    user_id_jwt_field: "sub"           # JWT claim for user ID
    user_email_jwt_field: "email"      # JWT claim for email
    team_ids_jwt_field: "groups"       # JWT claim for teams (array)
    public_key_ttl: 600                # Cache JWKS for 10 minutes

# Environment variable required:
# JWT_PUBLIC_KEY_URL=https://your-idp.okta.com/.well-known/jwks.json
```

**How it works:**

1. **Developer logs in via SSO** (one-time setup):
   ```bash
   # Using a helper script or browser flow
   codex-auth login
   # Opens browser → Okta login → Gets JWT token
   # Saves to ~/.codex/jwt_token
   ```

2. **Developer uses JWT as API key**:
   ```bash
   export OPENAI_API_KEY=$(cat ~/.codex/jwt_token)
   codex -c "explain this code" --file app.py
   ```

3. **Gateway validates JWT**:
   - Fetch JWKS from IdP (cached for 10 minutes)
   - Verify JWT signature
   - Extract claims: `sub` (user ID), `email`, `groups` (teams)
   - Query: `SELECT * FROM users WHERE user_id = jwt.sub`
   - Check quota for user/team
   - Use gateway's IAM role to call Bedrock

**Example JWT token payload:**
```json
{
  "sub": "00u1a2b3c4d5e6f7g8h9",           // User ID
  "email": "developer@company.com",
  "name": "Jane Developer",
  "groups": ["engineering", "ml-team"],    // Team membership
  "iss": "https://company.okta.com",
  "aud": "api://litellm-gateway",
  "iat": 1715000000,
  "exp": 1715003600                        // Expires in 1 hour
}
```

**Auto team mapping:**
```yaml
# LiteLLM auto-creates/assigns teams from JWT groups claim
# If JWT has "groups": ["engineering", "ml-team"]
# → User assigned to LiteLLM teams: engineering, ml-team
# → Team quotas apply automatically
```

## Enabling OIDC/JWT (Enterprise Only)

### Prerequisites

1. **LiteLLM Enterprise license**
   - Contact LiteLLM for pricing
   - Enterprise features include: JWT auth, SSO UI, advanced RBAC

2. **OIDC-compliant IdP**
   - Okta
   - Azure Active Directory (Microsoft Entra ID)
   - Auth0
   - AWS Cognito User Pools
   - Google Workspace
   - Any OIDC 1.0 compliant provider

### Configuration Steps

1. **Update litellm_config.yaml**:
   ```yaml
   general_settings:
     enable_jwt_auth: true
     litellm_jwtauth:
       user_id_jwt_field: "sub"
       user_email_jwt_field: "email"
       team_ids_jwt_field: "groups"  # Adjust to your IdP's claim name
       public_key_ttl: 600
   ```

2. **Set environment variable in ECS task definition**:
   ```yaml
   # In deployment/infrastructure/litellm-ecs.yaml
   Environment:
     - Name: JWT_PUBLIC_KEY_URL
       Value: https://company.okta.com/.well-known/jwks.json
   ```

3. **Configure IdP application**:
   - Create OIDC application in your IdP
   - Audience: `api://litellm-gateway` (or your gateway URL)
   - Scopes: `openid`, `email`, `profile`, `groups`
   - Token lifetime: 1 hour (recommended)

4. **Build and deploy updated image**:
   ```bash
   cxwb build --profile default
   cxwb deploy --profile default
   ```

### Developer Workflow with JWT

**Option A: Manual Token Fetch**
```bash
# Get token from IdP
TOKEN=$(curl -X POST https://company.okta.com/oauth2/default/v1/token \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "scope=openai" | jq -r '.access_token')

# Use token
export OPENAI_API_KEY="$TOKEN"
codex -c "explain code" --file app.py
```

**Option B: Helper Script** (recommended)
```bash
# Create scripts/codex-auth.sh
#!/bin/bash
# Opens browser for SSO login, gets token, saves to ~/.codex/jwt_token

codex-auth login
# → Opens browser → Okta login → Token saved

export OPENAI_API_KEY=$(cat ~/.codex/jwt_token)
codex -c "explain code" --file app.py
```

**Option C: Token Refresh Daemon**
```bash
# Background process that refreshes token before expiry
codex-auth daemon &
# Now OPENAI_API_KEY always has a valid token
```

## Hybrid Mode: Both API Keys AND JWT

LiteLLM can support both simultaneously:

```yaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY  # API keys still work
  enable_jwt_auth: true                      # JWT also works
  litellm_jwtauth:
    user_id_jwt_field: "sub"
    # ...
```

**Use case:** Gradual migration
- Internal employees: Use JWT (SSO integration)
- External contractors: Use API keys (no IdP access)
- CI/CD systems: Use long-lived API keys
- Interactive users: Use short-lived JWT tokens

## Security Considerations

### API Keys
✓ Long-lived (good for automation)
✓ Can be stored in CI/CD secrets
✗ Need secure distribution (Slack/email risky)
✗ Manual revocation required
✗ Harder to audit (key != person if shared)

### JWT/OIDC
✓ Auto-revocation when user disabled in IdP
✓ Short-lived (reduced blast radius)
✓ Audit trail via IdP logs
✓ MFA enforcement via IdP
✗ Requires browser for initial login
✗ Token refresh complexity
✗ Doesn't work well for CI/CD (use API keys instead)

## Recommendation

**For enterprise deployments with existing SSO:**

1. **Enable OIDC/JWT for interactive users** (developers at workstations)
2. **Keep API keys for automation** (CI/CD, cron jobs, scripts)
3. **Use hybrid mode** to support both

**For open-source/small teams:**

1. **Use API keys** (simpler, no Enterprise license needed)
2. **Implement key rotation policy** (regenerate every 90 days)
3. **Use self-service portal** (https://gateway/sso/key/generate)

## Cost Comparison

| Scenario | API Keys (Open-source) | OIDC/JWT (Enterprise) |
|----------|------------------------|----------------------|
| 10 users | $0 | ~$500-1000/month |
| 50 users | $0 | ~$1500-2500/month |
| 200 users | $0 | ~$5000-10000/month |

*Enterprise pricing varies - contact LiteLLM for quotes*

**Break-even analysis:**
- If you already pay for an IdP (Okta/Azure AD) and want tight integration: JWT worth it at 50+ users
- If you're OK with manual key management: API keys sufficient even at 200+ users

## Next Steps

**If staying with API keys:**
- ✅ Current config is ready
- Implement key distribution via `cxwb distribute`
- Set up self-service portal or admin key generation

**If enabling JWT:**
1. Purchase LiteLLM Enterprise license
2. Configure IdP application (Okta/Azure AD)
3. Uncomment JWT config in litellm_config.yaml
4. Add JWT_PUBLIC_KEY_URL to ECS environment
5. Create developer helper scripts for token management
6. Update developer bundle with JWT login instructions

## References

- [LiteLLM JWT Auth Docs](https://docs.litellm.ai/docs/proxy/jwt_auth)
- [LiteLLM Enterprise Features](https://www.litellm.ai/enterprise)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
