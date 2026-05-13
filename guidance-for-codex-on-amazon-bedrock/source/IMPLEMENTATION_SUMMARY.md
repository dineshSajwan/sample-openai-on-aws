# LiteLLM Image Automation - Implementation Summary

## Files Modified/Created

### New Files
1. **source/cxwb/commands/build.py** (148 lines)
   - Core build automation logic
   - ECR repository creation (idempotent)
   - Docker authentication and image building
   - Profile update with image_uri

2. **source/LITELLM_IMAGE_BUILD.md**
   - Complete documentation for build workflow
   - Troubleshooting guide
   - Version management instructions

3. **source/poetry.lock** (generated)
   - Dependency lock file from poetry install

### Modified Files
1. **source/cxwb/__init__.py** (+10 lines)
   - Added `LITELLM_RECOMMENDED_VERSION = "main-v1.82.3-stable.patch.2"`
   - Added `LITELLM_STABLE_VERSIONS` list with 4 versions

2. **source/cxwb/cli.py** (+7 lines)
   - Imported `build_cmd` module
   - Registered `build` command

3. **source/cxwb/commands/init.py** (+56 lines, ~7 lines modified)
   - Added image selection prompt (auto-build vs existing)
   - Added LiteLLM version selection from LITELLM_STABLE_VERSIONS
   - Added ECR repository name prompt
   - Restructured `_gateway_flow()` function

4. **source/cxwb/commands/deploy.py** (+17 lines)
   - Added validation to check `image_uri` exists before deploy
   - Added helpful error messages directing users to run `cxwb build`

5. **guidance-for-codex-on-amazon-bedrock/deployment/litellm/Dockerfile** (+3 lines, -1 line)
   - Added `ARG LITELLM_VERSION=main-latest`
   - Made base image version parameterized: `${LITELLM_VERSION}`

6. **guidance-for-codex-on-amazon-bedrock/README.md** (+385 lines, -142 lines)
   - Pre-existing changes, not related to this feature

7. **README.md** (root) (+95 lines, smaller changes)
   - Pre-existing changes, not related to this feature

### Untracked Files (not part of this feature)
- `../QUICKSTART_PATTERN_IDC.md`
- `../QUICKSTART_PATTERN_GATEWAY.md`
- `../QUICKSTART_PATTERN_HYBRID.md`

---

## What Changed - Detailed Breakdown

### 1. Profile Schema Updates

Gateway profiles now store additional fields:

```json
{
  "auth": "gateway",
  "manages_infra": true,
  
  // NEW FIELDS:
  "auto_build": true,                    // Whether to use cxwb build
  "litellm_version": "main-v1.82.3...",  // Selected LiteLLM version
  "ecr_repo_name": "codex-litellm-gateway", // ECR repository name
  
  // EXISTING FIELD (now set by cxwb build OR init):
  "image_uri": "123456.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3...",
  
  // ... rest unchanged
}
```

### 2. New Workflow: Auto-Build

**Before (required manual Docker work):**
```bash
# Manual ECR setup
aws ecr create-repository --repository-name litellm
aws ecr get-login-password | docker login ...
docker build -t litellm .
docker tag litellm 123456.dkr.ecr.us-west-2.amazonaws.com/litellm:latest
docker push 123456.dkr.ecr.us-west-2.amazonaws.com/litellm:latest

# Then provide URI to cxwb init
cxwb init
# Enter image URI: 123456.dkr.ecr.us-west-2.amazonaws.com/litellm:latest

cxwb deploy
```

**After (automated):**
```bash
cxwb init
# Select: "Build automatically from official LiteLLM image (Recommended)"
# Select version: "main-v1.82.3-stable.patch.2 (Recommended)"

cxwb build     # All Docker/ECR work automated
cxwb deploy
```

### 3. Build Command Implementation

**What `cxwb build` does:**

1. **Loads profile** and validates it's a gateway profile with `auto_build: true`

2. **Creates ECR repository** (idempotent):
   ```python
   ecr.describe_repositories(repositoryNames=[repo_name])
   # If not exists:
   ecr.create_repository(repositoryName=repo_name, tags=[...])
   ```

3. **Docker login to ECR**:
   ```python
   token = ecr.get_authorization_token()
   subprocess.run(["docker", "login", "--username", "AWS", ...])
   ```

4. **Builds Docker image**:
   ```bash
   docker build \
     --build-arg LITELLM_VERSION=main-v1.82.3-stable.patch.2 \
     -t 123456.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3... \
     -f deployment/litellm/Dockerfile \
     deployment/litellm/
   ```

5. **Pushes to ECR**:
   ```bash
   docker push 123456.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3...
   ```

6. **Updates profile** with final `image_uri`

### 4. Deploy Validation

**New behavior in `cxwb deploy`:**

```python
# Before deploying gateway stack:
if "image_uri" not in profile or not profile["image_uri"]:
    if profile.get("auto_build"):
        # User selected auto-build but hasn't run build yet
        raise ClickException("Missing image_uri — run `cxwb build` first")
    else:
        # User selected existing image but didn't provide URI
        raise ClickException("Missing image_uri in profile")
```

Prevents deployment failures with clear error messages.

---

## How End Users Access Codex (Already Documented)

### Step 1: Admin Deploys Gateway (New Workflow)

```bash
cd guidance-for-codex-on-amazon-bedrock/source/

# Initialize profile
poetry run cxwb init
# Select: "LiteLLM Gateway — deploy new"
# Select: "Build automatically from official LiteLLM image"
# Select version: "main-v1.82.3-stable.patch.2 (Recommended)"

# Build Docker image
poetry run cxwb build --profile default

# Deploy infrastructure
poetry run cxwb deploy --profile default
# Output: GatewayEndpoint = https://codex-alb-123456.us-west-2.elb.amazonaws.com
```

### Step 2: Admin Distributes Bundle to Developers

```bash
# Generate developer bundle
poetry run cxwb distribute --profile default --bucket my-s3-bucket

# Output:
# ✓ Bundle created: ./dist/codex-bundle/
# ✓ Uploaded to S3: s3://my-s3-bucket/default/codex-bundle.zip
# ✓ Presigned URL (7 days): https://my-s3-bucket.s3.amazonaws.com/...
```

**Bundle contents:**
```
codex-bundle/
├── install.sh              # Developer runs this
├── uninstall.sh            # Cleanup
├── config.toml.snippet     # Codex configuration
├── DEV-SETUP.md            # Instructions
└── env.template            # Template for OPENAI_API_KEY
```

### Step 3: Developer Setup (from DEV-SETUP.md)

**Option A: Using LiteLLM Self-Service Portal (if enabled)**

1. Download and extract bundle:
   ```bash
   wget "<presigned-url>" -O codex-bundle.zip
   unzip codex-bundle.zip
   cd codex-bundle/
   ```

2. Get API key from self-service portal:
   ```bash
   # Open browser to:
   https://codex-alb-123456.us-west-2.elb.amazonaws.com/sso/key/generate
   
   # Login with corporate SSO (Okta/Azure AD)
   # Copy API key: sk-1234567890abcdef...
   ```

3. Run install script:
   ```bash
   export OPENAI_API_KEY="sk-1234567890abcdef..."
   ./install.sh
   ```

4. Verify setup:
   ```bash
   codex --version
   codex -c "print hello world" python
   ```

**Option B: Admin-Provided API Keys**

If self-service portal is not enabled, admin generates keys:

```bash
# Admin generates key for developer
curl -X POST https://codex-alb-123456.us-west-2.elb.amazonaws.com/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "developer@company.com",
    "max_budget": 100.0,
    "duration": "30d"
  }'

# Response: {"key": "sk-abc123..."}
```

Admin sends key to developer, who then runs install.sh.

### Step 4: Developer Uses Codex

The installed config points to the gateway:

```toml
# ~/.codex/config.toml
model_provider = "openai"
model = "openai.gpt-5.4"

[openai]
base_url = "https://codex-alb-123456.us-west-2.elb.amazonaws.com/v1"
# api_key from OPENAI_API_KEY environment variable
```

**Usage:**
```bash
# Set API key (once per session)
export OPENAI_API_KEY="sk-1234567890abcdef..."

# Use Codex normally
codex -c "add error handling to this function" --file app.py
codex chat
codex -m gpt-oss-120b -c "explain this architecture" --file README.md
```

**Behind the scenes:**
```
Developer Machine                Gateway (ECS)              AWS Bedrock
┌────────────────┐             ┌──────────────┐          ┌─────────────┐
│ codex CLI      │             │ LiteLLM      │          │ GPT-5.4     │
│                │  HTTP POST  │              │  AWS SDK │             │
│ OPENAI_API_KEY │────────────▶│ - Validate   │─────────▶│ gpt-5.4     │
│ base_url=gw    │             │ - Quota      │          │ inference   │
│                │◀────────────│ - Transform  │◀─────────│             │
│                │  streaming  │ - Observe    │          │             │
└────────────────┘             └──────────────┘          └─────────────┘
```

**Key features for developers:**
- ✅ No AWS credentials needed
- ✅ No AWS CLI setup
- ✅ No IAM IdC login flow
- ✅ Standard OpenAI API format (works with existing tools)
- ✅ Hard quota limits (request blocked if over budget)
- ✅ Rate limiting (RPM/TPM enforcement)
- ✅ Centralized observability (OTel metrics)

---

## Files to Review Before Committing

### Core Implementation (must review)
```bash
git diff source/cxwb/commands/build.py      # New file - 148 lines
git diff source/cxwb/__init__.py            # +10 lines (version constants)
git diff source/cxwb/cli.py                 # +7 lines (build command)
git diff source/cxwb/commands/init.py       # +56 lines (image selection)
git diff source/cxwb/commands/deploy.py     # +17 lines (validation)
git diff ../deployment/litellm/Dockerfile   # +3 lines (ARG support)
```

### Documentation (review)
```bash
cat source/LITELLM_IMAGE_BUILD.md          # New comprehensive docs
```

### Not part of this feature (ignore for now)
```bash
# These were modified in earlier work:
git diff ../../README.md
git diff ../README.md

# These are untracked (pattern docs):
ls ../QUICKSTART_PATTERN*.md
```

---

## Testing Checklist

Before committing, test the following workflows:

### Test 1: Auto-Build Happy Path
```bash
# Clean slate
rm -rf ~/.cxwb/profiles/test-auto.json

# Initialize with auto-build
poetry run cxwb init
# Name: test-auto
# Select: "LiteLLM Gateway — deploy new"
# Select: "Build automatically from official LiteLLM image"
# Select: "main-v1.82.3-stable.patch.2 (Recommended)"
# ECR repo: test-codex-litellm

# Verify profile
cat ~/.cxwb/profiles/test-auto.json | jq '.auto_build, .litellm_version, .ecr_repo_name'
# Expected:
# true
# "main-v1.82.3-stable.patch.2"
# "test-codex-litellm"

# Build (requires Docker running + AWS credentials)
poetry run cxwb build --profile test-auto
# Expected: Success, image pushed to ECR

# Verify image_uri added to profile
cat ~/.cxwb/profiles/test-auto.json | jq '.image_uri'
# Expected: "<account>.dkr.ecr.<region>.amazonaws.com/test-codex-litellm:main-v1.82.3..."

# Test deploy validation (don't actually deploy)
# Should pass validation now that image_uri exists
```

### Test 2: Existing Image Path
```bash
# Initialize with existing image
poetry run cxwb init
# Name: test-existing
# Select: "LiteLLM Gateway — deploy new"
# Select: "Use existing image from my ECR repository"
# Image URI: "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-litellm:v1.80.0"

# Verify profile
cat ~/.cxwb/profiles/test-existing.json | jq '.auto_build, .image_uri'
# Expected:
# false
# "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-litellm:v1.80.0"

# Build should fail (not auto-build profile)
poetry run cxwb build --profile test-existing
# Expected error: "Build command only applies to profiles that manage infrastructure"
```

### Test 3: Deploy Without Build
```bash
# Initialize auto-build but skip build step
poetry run cxwb init
# Name: test-nobuild
# Select auto-build

# Try to deploy without building
poetry run cxwb deploy --profile test-nobuild
# Expected error: "Missing image_uri — run `cxwb build` first"
```

### Test 4: Version Selection
```bash
# Verify all versions appear in prompt
poetry run python -c "from cxwb import LITELLM_STABLE_VERSIONS; print('\n'.join(LITELLM_STABLE_VERSIONS))"
# Expected:
# main-v1.82.3-stable.patch.2
# main-v1.80.5-stable
# main-v1.78.0-stable
# main-latest
```

### Test 5: Dockerfile ARG
```bash
# Build with different version
cd ../deployment/litellm/
docker build --build-arg LITELLM_VERSION=main-v1.80.5-stable -t test:v1.80 .
# Expected: Success, pulls ghcr.io/berriai/litellm:main-v1.80.5-stable
```

---

## Next Steps After Commit

Once you commit and test this feature, the next task is:

**Choose Multi-Account Access Pattern:**

1. **VPC PrivateLink** - Fully private, no public internet
2. **CloudFront + Secret Header** - Public internet with validation
3. **API Gateway Private** - Hybrid approach

Each requires additional CloudFormation templates and cxwb updates.
