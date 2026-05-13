# LiteLLM Image Build Automation

This document explains how `cxwb` automates building and pushing LiteLLM Docker images to ECR.

## Overview

The `cxwb build` command automates:
1. Creating an ECR repository (if it doesn't exist)
2. Authenticating Docker to ECR
3. Building a Docker image from the official LiteLLM base image
4. Pushing the image to your ECR repository
5. Updating your profile with the image URI

## Workflow

### Option 1: Auto-Build (Recommended)

When you run `cxwb init` and select "Build automatically from official LiteLLM image":

```bash
# Step 1: Initialize profile with auto-build
$ cxwb init
# Select: "LiteLLM Gateway — deploy new"
# Select: "Build automatically from official LiteLLM image (Recommended)"
# Select LiteLLM version: "main-v1.82.3-stable.patch.2 (Recommended)"
# Provide ECR repository name: "codex-litellm-gateway"

# Step 2: Build the Docker image
$ cxwb build --profile default

# Step 3: Deploy infrastructure
$ cxwb deploy --profile default
```

**What happens during `cxwb build`:**
1. Reads `litellm_version` from your profile (e.g., `main-v1.82.3-stable.patch.2`)
2. Creates ECR repository `codex-litellm-gateway` in your AWS account
3. Runs Docker login to authenticate with ECR
4. Builds Docker image:
   ```dockerfile
   FROM ghcr.io/berriai/litellm:main-v1.82.3-stable.patch.2
   COPY litellm_config.yaml /app/config.yaml
   ```
5. Tags image as `<account-id>.dkr.ecr.<region>.amazonaws.com/codex-litellm-gateway:main-v1.82.3-stable.patch.2`
6. Pushes to ECR
7. Updates profile with `image_uri` for deployment

### Option 2: Use Existing Image

When you select "Use existing image from my ECR repository":

```bash
# Step 1: Initialize with existing image
$ cxwb init
# Select: "LiteLLM Gateway — deploy new"
# Select: "Use existing image from my ECR repository"
# Provide image URI: "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-litellm:v1.80.0"

# Step 2: Deploy (no build needed)
$ cxwb deploy --profile default
```

## LiteLLM Versions

Available stable versions (configurable in `cxwb/__init__.py`):
- `main-v1.82.3-stable.patch.2` (Recommended)
- `main-v1.80.5-stable`
- `main-v1.78.0-stable`
- `main-latest`

You can find more versions at: https://github.com/berriai/litellm/pkgs/container/litellm/versions

## Custom Configuration

The build process uses two local files:

### `deployment/litellm/Dockerfile`
```dockerfile
ARG LITELLM_VERSION=main-latest
FROM ghcr.io/berriai/litellm:${LITELLM_VERSION}
COPY litellm_config.yaml /app/config.yaml
```

### `deployment/litellm/litellm_config.yaml`
Defines the model mappings and LiteLLM configuration:
- OpenAI Codex models via Bedrock (gpt-4o, gpt-4o-mini, gpt-oss-120b)
- Claude models as fallback
- OTel callback for observability
- Master key authentication

**To customize:** Edit `litellm_config.yaml` before running `cxwb build`.

## Prerequisites

- AWS CLI configured with credentials
- Docker installed and running
- IAM permissions:
  - `ecr:CreateRepository`
  - `ecr:DescribeRepositories`
  - `ecr:GetAuthorizationToken`
  - `ecr:InitiateLayerUpload`
  - `ecr:UploadLayerPart`
  - `ecr:CompleteLayerUpload`
  - `ecr:PutImage`
  - `sts:GetCallerIdentity`

## Error Handling

### "Profile 'X' not found"
Run `cxwb init` first to create a profile.

### "Build command only applies to gateway profiles"
The build command only works with `LiteLLM Gateway — deploy new` profiles.

### "Docker build failed"
- Check Docker is running: `docker ps`
- Verify base image exists: https://github.com/berriai/litellm/pkgs/container/litellm
- Check `deployment/litellm/Dockerfile` syntax

### "Docker push failed"
- Verify AWS credentials: `aws sts get-caller-identity`
- Check ECR permissions
- Ensure Docker login succeeded

### "Missing image_uri — run `cxwb build` first"
When deploying an auto-build profile, you must run `cxwb build` before `cxwb deploy`.

## Profile Storage

Profiles are stored in `~/.cxwb/profiles/<name>.json` with permissions `0600`.

Example profile after `cxwb build`:
```json
{
  "auth": "gateway",
  "auto_build": true,
  "ecr_repo_name": "codex-litellm-gateway",
  "gateway_stack": "codex-litellm-gateway",
  "image_uri": "123456789012.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3-stable.patch.2",
  "litellm_version": "main-v1.82.3-stable.patch.2",
  "manages_infra": true,
  "region": "us-west-2",
  ...
}
```

## Updating LiteLLM Version

To upgrade to a newer LiteLLM version:

1. Edit your profile or re-run `cxwb init` with the new version
2. Run `cxwb build` to build the new image
3. Run `cxwb deploy` to update the ECS service

The new image tag will be different (e.g., `:main-v1.83.0-stable`), so ECS will pull the new version.

## Architecture

```
Developer Machine                  AWS
┌────────────────┐                ┌──────────────────────────┐
│ cxwb build     │                │ ECR Repository           │
│                │ docker push    │ codex-litellm-gateway    │
│ 1. ECR create  │───────────────▶│  :main-v1.82.3-stable... │
│ 2. ECR login   │                │  :main-v1.80.5-stable    │
│ 3. Docker build│                │  :main-latest            │
│ 4. Docker push │                └──────────────────────────┘
│ 5. Update prof │                         │
└────────────────┘                         │ ECS pulls
                                           ▼
                                  ┌──────────────────────────┐
Developer runs:                   │ ECS Fargate Task         │
cxwb deploy                       │ LiteLLM Gateway          │
  └─▶ CloudFormation              │ + custom config.yaml     │
      creates ECS service         └──────────────────────────┘
```

## Comparison with Other Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Auto-build (cxwb build)** | Simple workflow, version-controlled config, reproducible | Requires Docker locally |
| **Existing image** | Flexibility, use any registry | Manual image management |
| **Manual ECR push** | Full control | More steps, error-prone |
| **Build from source** | Customize LiteLLM code | Complex, long build times |

**Recommendation:** Use auto-build for standard deployments. Only use "existing image" if you have custom LiteLLM modifications or a CI/CD pipeline that builds images separately.
