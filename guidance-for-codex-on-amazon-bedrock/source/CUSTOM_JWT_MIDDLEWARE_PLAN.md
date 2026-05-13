# Custom JWT Middleware Implementation Plan

## Overview

Add OIDC/JWT authentication support **without** requiring LiteLLM Enterprise license by building custom middleware (similar to [AWS Multi-Provider Gateway](https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws)).

## Current State

**What Works Today:**
- ✅ Admin generates API keys via LiteLLM UI
- ✅ Developers set `OPENAI_API_KEY` in environment
- ✅ Gateway validates API keys and tracks usage

**What's Missing:**
- ❌ Developers can't self-generate keys via SSO
- ❌ No OIDC/JWT integration with corporate IdP
- ❌ Manual key distribution required

## Proposed Architecture

### Flow with Custom JWT Middleware

```
Developer → Corporate IdP (Okta/Azure AD) → JWT Token
         ↓
JWT Middleware Container (new)
         ↓
Validates JWT, extracts user identity
         ↓
Looks up or creates LiteLLM API key for user
         ↓
Forwards request to LiteLLM with API key
         ↓
LiteLLM Gateway → Bedrock
```

### Components to Build

1. **JWT Validation Middleware** (Python Flask/FastAPI)
   - Validates JWT tokens from IdP
   - Extracts claims: `sub`, `email`, `groups`
   - Caches validated tokens (Redis)
   
2. **User-to-Key Mapping Service**
   - Maps user identity → LiteLLM API key
   - Auto-creates keys for new users
   - Stores mapping in RDS/DynamoDB

3. **ECS Sidecar Container**
   - Runs alongside LiteLLM container
   - Intercepts all requests
   - Adds validated API key to LiteLLM request

## Implementation Steps

### Phase 1: JWT Validation Layer (2-3 days)

**1.1 Create Middleware Service**

**File:** `deployment/litellm/jwt-middleware/app.py`

```python
from flask import Flask, request, jsonify
import jwt
import requests
from functools import lru_cache
import os

app = Flask(__name__)

JWKS_URL = os.environ['JWKS_URL']  # e.g., https://your-tenant.okta.com/.well-known/jwks.json
LITELLM_URL = os.environ['LITELLM_URL']  # http://localhost:4000
LITELLM_MASTER_KEY = os.environ['LITELLM_MASTER_KEY']

@lru_cache(maxsize=1)
def get_jwks():
    """Fetch and cache JWKS from IdP"""
    response = requests.get(JWKS_URL)
    return response.json()

def validate_jwt(token):
    """Validate JWT token from Authorization header"""
    try:
        # Get JWKS
        jwks = get_jwks()
        
        # Decode and validate
        unverified_header = jwt.get_unverified_header(token)
        key = next(k for k in jwks['keys'] if k['kid'] == unverified_header['kid'])
        
        # Verify signature and expiration
        payload = jwt.decode(
            token,
            key=key,
            algorithms=['RS256'],
            audience=os.environ.get('JWT_AUDIENCE'),
            issuer=os.environ.get('JWT_ISSUER')
        )
        
        return {
            'user_id': payload['sub'],
            'email': payload.get('email'),
            'groups': payload.get('groups', [])
        }
    except Exception as e:
        raise ValueError(f"Invalid JWT: {e}")

def get_or_create_api_key(user_info):
    """Get existing API key for user or create new one"""
    # Check cache (Redis) first
    # If not cached, query LiteLLM API
    # If no key exists, create one via LiteLLM API
    
    # For now, simplified:
    response = requests.post(
        f"{LITELLM_URL}/key/generate",
        headers={'Authorization': f'Bearer {LITELLM_MASTER_KEY}'},
        json={
            'key_alias': user_info['email'],
            'user_id': user_info['user_id'],
            'metadata': {
                'groups': user_info['groups'],
                'managed_by': 'jwt-middleware'
            }
        }
    )
    
    if response.status_code == 200:
        return response.json()['key']
    
    # If key already exists, fetch it
    # (Requires querying LiteLLM database or caching)
    raise Exception("Key creation failed")

@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def proxy(path):
    """Proxy all requests to LiteLLM after JWT validation"""
    
    # Extract JWT from Authorization header
    auth_header = request.headers.get('Authorization', '')
    
    if not auth_header.startswith('Bearer '):
        return jsonify({'error': 'Missing Authorization header'}), 401
    
    token = auth_header.split(' ')[1]
    
    # Validate JWT and extract user identity
    try:
        user_info = validate_jwt(token)
    except ValueError as e:
        return jsonify({'error': str(e)}), 401
    
    # Get or create API key for this user
    try:
        api_key = get_or_create_api_key(user_info)
    except Exception as e:
        return jsonify({'error': f'Key management failed: {e}'}), 500
    
    # Forward request to LiteLLM with API key
    litellm_url = f"{LITELLM_URL}/{path}"
    headers = dict(request.headers)
    headers['Authorization'] = f'Bearer {api_key}'
    
    response = requests.request(
        method=request.method,
        url=litellm_url,
        headers=headers,
        json=request.get_json() if request.is_json else None,
        params=request.args,
        stream=True  # Important for streaming responses
    )
    
    return response.content, response.status_code, dict(response.headers)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**1.2 Create Dockerfile**

**File:** `deployment/litellm/jwt-middleware/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "app:app"]
```

**File:** `deployment/litellm/jwt-middleware/requirements.txt`

```
Flask==3.0.0
gunicorn==21.2.0
PyJWT==2.8.0
cryptography==41.0.7
requests==2.31.0
redis==5.0.1
```

### Phase 2: ECS Task Definition Updates (1 day)

**2.1 Update CloudFormation to Deploy Sidecar**

**File:** `deployment/litellm/ecs/litellm-ecs.yaml`

Add JWT middleware container to task definition:

```yaml
Resources:
  TaskDefinition:
    Properties:
      ContainerDefinitions:
        # Existing LiteLLM container
        - Name: litellm
          Image: !Ref LiteLLMImage
          PortMappings:
            - ContainerPort: 4000
          Environment:
            - Name: LITELLM_MASTER_KEY
              ValueFrom: !Ref LiteLLMSecret
          # ... existing config
        
        # NEW: JWT Middleware container
        - Name: jwt-middleware
          Image: !Sub '${AWS::AccountId}.dkr.ecr.${AWS::Region}.amazonaws.com/codex-jwt-middleware:latest'
          PortMappings:
            - ContainerPort: 8080  # This is what ALB targets now
          Environment:
            - Name: JWKS_URL
              Value: !Ref JwksUrl
            - Name: JWT_AUDIENCE
              Value: !Ref JwtAudience
            - Name: JWT_ISSUER
              Value: !Ref JwtIssuer
            - Name: LITELLM_URL
              Value: 'http://localhost:4000'  # Same task, different container
            - Name: LITELLM_MASTER_KEY
              ValueFrom: !Ref LiteLLMSecret
          DependsOn:
            - ContainerName: litellm
              Condition: START

  # Update ALB target to point to middleware (port 8080), not LiteLLM (port 4000)
  TargetGroup:
    Properties:
      Port: 8080  # Changed from 4000
```

**2.2 Add New Parameters**

```yaml
Parameters:
  JwksUrl:
    Type: String
    Description: JWKS URL from IdP (e.g., https://tenant.okta.com/.well-known/jwks.json)
  
  JwtAudience:
    Type: String
    Description: Expected JWT audience claim
  
  JwtIssuer:
    Type: String
    Description: Expected JWT issuer claim
```

### Phase 3: User-to-Key Mapping (2 days)

**3.1 Create DynamoDB Table for Mapping**

```yaml
Resources:
  UserKeyMappingTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: codex-user-keys
      AttributeDefinitions:
        - AttributeName: user_id
          AttributeType: S
      KeySchema:
        - AttributeName: user_id
          KeyType: HASH
      BillingMode: PAY_PER_REQUEST
      TimeToLiveSpecification:
        Enabled: true
        AttributeName: ttl
```

**3.2 Update Middleware to Use DynamoDB**

Cache user → API key mappings to avoid creating duplicate keys:

```python
import boto3

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('codex-user-keys')

def get_cached_key(user_id):
    """Get cached API key for user"""
    response = table.get_item(Key={'user_id': user_id})
    return response.get('Item', {}).get('api_key')

def cache_key(user_id, api_key):
    """Cache user → API key mapping"""
    table.put_item(Item={
        'user_id': user_id,
        'api_key': api_key,
        'ttl': int(time.time()) + 86400 * 90  # 90 days
    })
```

### Phase 4: cxwb Integration (1 day)

**4.1 Update `cxwb init` Wizard**

Add OIDC configuration prompts:

```python
# In source/cxwb/commands/init.py

if enable_oidc:
    data.update({
        "enable_oidc": True,
        "jwks_url": _text("JWKS URL (e.g., https://tenant.okta.com/.well-known/jwks.json):"),
        "jwt_audience": _text("JWT Audience:"),
        "jwt_issuer": _text("JWT Issuer:"),
    })
```

**4.2 Add `cxwb build-jwt-middleware` Command**

```python
# In source/cxwb/cli.py

@cli.command(help="Build and push JWT middleware image to ECR.")
@click.option("--profile", "profile_name", default="default", show_default=True)
def build_jwt_middleware(profile_name: str) -> None:
    """Build JWT middleware Docker image"""
    # Similar to build command, but for jwt-middleware/
```

### Phase 5: Developer Experience (1 day)

**5.1 Self-Service Portal**

Create simple HTML page at `/sso/key/generate`:

```html
<!-- Hosted on S3 or served by middleware -->
<!DOCTYPE html>
<html>
<head><title>Get Your Codex API Key</title></head>
<body>
  <h1>Codex API Key Generator</h1>
  <button onclick="authenticate()">Sign in with SSO</button>
  <div id="result"></div>
  
  <script>
    function authenticate() {
      // Redirect to IdP OAuth2 authorize endpoint
      window.location = 'https://your-tenant.okta.com/oauth2/authorize?' +
        'client_id=YOUR_CLIENT_ID&' +
        'response_type=token&' +
        'scope=openid email profile&' +
        'redirect_uri=' + encodeURIComponent(window.location.origin + '/callback');
    }
    
    // On callback page, extract JWT from URL hash
    const hash = window.location.hash.substring(1);
    const params = new URLSearchParams(hash);
    const jwt = params.get('access_token');
    
    if (jwt) {
      // Call middleware to get API key
      fetch('/api/my-key', {
        headers: {'Authorization': 'Bearer ' + jwt}
      })
      .then(r => r.json())
      .then(data => {
        document.getElementById('result').innerHTML = 
          '<h2>Your API Key:</h2><code>' + data.api_key + '</code>';
      });
    }
  </script>
</body>
</html>
```

**5.2 Add `/api/my-key` Endpoint to Middleware**

```python
@app.route('/api/my-key', methods=['GET'])
def get_my_key():
    """Return API key for authenticated user"""
    token = request.headers.get('Authorization', '').split(' ')[1]
    user_info = validate_jwt(token)
    api_key = get_or_create_api_key(user_info)
    
    return jsonify({
        'api_key': api_key,
        'user_id': user_info['user_id'],
        'email': user_info['email']
    })
```

## Testing Plan

1. **Unit Tests** (jwt-middleware/tests/)
   - Test JWT validation with valid/invalid tokens
   - Test key creation/caching logic
   - Test request proxying

2. **Integration Tests**
   - Deploy to dev environment
   - Test full flow: IdP → JWT → Middleware → LiteLLM → Bedrock
   - Test with real Okta/Azure AD tenant

3. **Load Tests**
   - Ensure middleware doesn't become bottleneck
   - Test caching effectiveness
   - Measure added latency (should be <50ms)

## Rollout Strategy

**Phase 1: Pilot (Week 1)**
- Deploy to single dev/test account
- 5-10 beta users test self-service portal
- Monitor logs, fix issues

**Phase 2: Gradual Rollout (Week 2-3)**
- Enable for one team at a time
- Keep admin-generated keys as fallback
- Monitor error rates, latency

**Phase 3: Full Production (Week 4)**
- Enable for all users
- Deprecate manual key generation
- Document in QUICKSTART_PATTERN_GATEWAY.md

## Estimated Effort

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| 1. JWT Middleware | 2-3 days | Python, Flask/FastAPI |
| 2. ECS Integration | 1 day | CloudFormation |
| 3. User Mapping | 2 days | DynamoDB, caching |
| 4. cxwb CLI | 1 day | Click, existing cxwb |
| 5. Dev Experience | 1 day | HTML/JS, OAuth2 |
| **Total** | **7-8 days** | |

## Cost Impact

**Additional AWS Services:**
- **DynamoDB Table**: ~$1-5/month (PAY_PER_REQUEST)
- **ECS Task CPU/Memory**: +0.25 vCPU, +512MB (~$5/month)
- **ECR Storage**: +100MB for middleware image (~$0.01/month)

**Total Additional Cost:** ~$6-10/month (minimal)

## Alternative: Use LiteLLM Enterprise

| Custom JWT Middleware | LiteLLM Enterprise |
|-----------------------|-------------------|
| **Cost:** $6-10/month AWS | **Cost:** $500-2000+/month license |
| **Effort:** 7-8 days dev | **Effort:** 1 day config |
| **Maintenance:** You own it | **Maintenance:** Vendor support |
| **Features:** Basic OIDC only | **Features:** Advanced routing, SSO, audit |
| **Support:** Self-support | **Support:** Enterprise support |

**Recommendation:** Start with custom middleware (lower cost, learn the system), upgrade to Enterprise later if needed (advanced features, vendor support).

## Success Criteria

- ✅ Developers can self-generate keys via SSO
- ✅ No manual admin intervention needed
- ✅ JWT validation <50ms added latency
- ✅ Key caching reduces database load
- ✅ Works with Okta, Azure AD, Auth0
- ✅ Documentation updated in QUICKSTART_PATTERN_GATEWAY.md

## References

- AWS Multi-Provider Gateway: https://github.com/aws-solutions-library-samples/guidance-for-multi-provider-generative-ai-gateway-on-aws
- LiteLLM API Docs: https://docs.litellm.ai/docs/proxy/token_auth
- PyJWT Documentation: https://pyjwt.readthedocs.io/
- OAuth 2.0 Flow: https://oauth.net/2/
