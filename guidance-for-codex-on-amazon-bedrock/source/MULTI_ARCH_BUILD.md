# Multi-Architecture Docker Build Support

## Overview

`cxwb build` now supports building Docker images for **both ARM64 and x86_64 architectures**, allowing you to:
- Build on ARM Mac (M1/M2/M3) and deploy to x86_64 ECS Fargate
- Build on x86_64 machine and deploy to ARM64 Graviton instances
- Create a single multi-arch image that works on both architectures

## Quick Start

### Default: Multi-Arch Build (Recommended)

```bash
poetry run cxwb build --profile codex-bedrock-gw
```

**What happens:**
- Detects your host architecture (ARM64 or x86_64)
- Builds image for **both** amd64 and arm64
- Pushes multi-arch manifest to ECR
- Works on both x86_64 and ARM64 ECS/EKS instances

**Output:**
```
🔨 Building LiteLLM image for profile: codex-bedrock-gw
  Region: us-west-2
  ECR repository: codex-litellm-gateway
  LiteLLM version: main-v1.82.3-stable.patch.2
  Multi-architecture: Yes (amd64 + arm64)
  
📦 Building Docker image...
  Base image: ghcr.io/berriai/litellm:main-v1.82.3-stable.patch.2
  Host architecture: arm64
  Target platforms: linux/amd64, linux/arm64
  Building for multiple architectures (amd64 + arm64)...
  This may take 2-3x longer than single-arch build
  
✓ Multi-arch image built and pushed
✓ Build complete. Profile updated with image_uri.

📦 Multi-arch image supports both:
  • x86_64 (amd64) - ECS Fargate default
  • ARM64 (arm64) - Graviton instances

Next: cxwb deploy --profile codex-bedrock-gw
```

### Single-Arch Build (Faster)

If you only need x86_64 (ECS Fargate standard):

```bash
poetry run cxwb build --profile codex-bedrock-gw --no-multi-arch
```

**What happens:**
- Builds image for **amd64 only**
- 2-3x faster than multi-arch
- Smaller image size
- Uses QEMU emulation if cross-compiling

## Architecture Detection

The tool automatically detects your host architecture:

| Host Machine | Detected As | Default Target |
|--------------|-------------|----------------|
| Mac M1/M2/M3 | `arm64` | linux/amd64 + linux/arm64 |
| Mac Intel | `amd64` | linux/amd64 + linux/arm64 |
| Linux ARM64 | `arm64` | linux/amd64 + linux/arm64 |
| Linux x86_64 | `amd64` | linux/amd64 + linux/arm64 |

## Cross-Compilation

### ARM Mac → x86_64 ECS

**Scenario:** You're on a Mac M1 and want to deploy to standard ECS Fargate (x86_64).

**Solution:** Multi-arch build (default) or single-arch with QEMU emulation.

**Command:**
```bash
# Option 1: Multi-arch (includes both architectures)
poetry run cxwb build --profile codex-bedrock-gw

# Option 2: Single-arch (amd64 only, using QEMU)
poetry run cxwb build --profile codex-bedrock-gw --no-multi-arch
```

**Warning shown:**
```
⚠️  Cross-compiling: ARM64 host → x86_64 target
   (Using QEMU emulation - build may be slower)
```

### x86_64 Machine → ARM64 Graviton

**Scenario:** You're on an Intel Mac/PC and want to deploy to ARM64 Graviton instances.

**Solution:** Multi-arch build automatically includes ARM64.

**Command:**
```bash
poetry run cxwb build --profile codex-bedrock-gw
```

The resulting image works on both architectures.

## Docker Buildx Requirement

Multi-arch builds require **Docker buildx**, which is included in:
- ✅ Docker Desktop for Mac (v4.0+)
- ✅ Docker Desktop for Windows (v4.0+)
- ✅ Docker Engine 19.03+ with buildx plugin

### Check Buildx Availability

```bash
docker buildx version
```

**If available:**
```
github.com/docker/buildx v0.12.0 ...
```

**If NOT available:**
```
docker: 'buildx' is not a docker command.
```

### Fallback Behavior

If buildx is not available:
- Tool automatically falls back to single-arch build (amd64)
- Shows warning: `⚠️  Docker buildx not available, falling back to single-arch build for amd64`
- Uses standard `docker build` with `--platform linux/amd64`

## Build Time Comparison

| Build Type | Time (M1 Mac) | Time (Intel Mac) |
|------------|---------------|------------------|
| **Single-arch (native)** | ~2-3 min | ~2-3 min |
| **Single-arch (cross-compile)** | ~4-6 min | ~4-6 min |
| **Multi-arch** | ~6-10 min | ~6-10 min |

Multi-arch builds take longer because they:
1. Pull base images for both architectures
2. Build for amd64 (may use QEMU if on ARM)
3. Build for arm64 (may use QEMU if on x86)
4. Create and push multi-arch manifest

## Multi-Arch Manifest

When you push a multi-arch image, ECR stores:

```
codex-litellm-gateway:main-v1.82.3-stable.patch.2  (manifest list)
  ├─ linux/amd64 (sha256:abc123...)
  └─ linux/arm64 (sha256:def456...)
```

**ECS/EKS automatically pulls the correct architecture:**
- x86_64 instance → pulls linux/amd64 layer
- ARM64 instance → pulls linux/arm64 layer

**Single image URI works for both:**
```
551246883740.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3-stable.patch.2
```

## Troubleshooting

### Error: "exec format error"

**Cause:** Image architecture doesn't match ECS instance architecture.

**Solution:**
1. Check what you built:
   ```bash
   docker manifest inspect 551246883740.dkr.ecr.us-west-2.amazonaws.com/codex-litellm-gateway:main-v1.82.3-stable.patch.2
   ```

2. Rebuild with multi-arch:
   ```bash
   poetry run cxwb build --profile codex-bedrock-gw
   ```

3. Force ECS to pull new image:
   ```bash
   aws ecs update-service \
     --cluster codex-litellm-gateway \
     --service <service-name> \
     --force-new-deployment \
     --region us-west-2
   ```

### Error: "failed to solve: failed to copy: httpReadSeeker: failed open: unexpected status code 403"

**Cause:** Buildx trying to pull image for unsupported architecture.

**Solution:** Verify base image supports both architectures:
```bash
docker manifest inspect ghcr.io/berriai/litellm:main-v1.82.3-stable.patch.2
```

If base image only supports one architecture, use `--no-multi-arch`.

### Warning: "QEMU emulation not enabled in Docker Desktop"

**Cause:** Docker Desktop's QEMU emulation is disabled.

**Solution:**
1. Open Docker Desktop
2. Settings → Features
3. Enable: "Use containerd for pulling and storing images"
4. Restart Docker Desktop
5. Retry build

### Build is Very Slow (>15 minutes)

**Cause:** QEMU emulation overhead for cross-compilation.

**Solutions:**
1. **Use native architecture:** If you don't need cross-platform, use `--no-multi-arch`
2. **Build on CI:** Use EC2/CodeBuild with native architecture
3. **Use Docker Buildx cache:** Subsequent builds are faster

## CI/CD Integration

### GitHub Actions

```yaml
name: Build Multi-Arch Image

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2
      
      - name: Install cxwb
        run: |
          cd guidance-for-codex-on-amazon-bedrock/source
          pip install poetry
          poetry install
      
      - name: Build and push image
        run: |
          cd guidance-for-codex-on-amazon-bedrock/source
          poetry run cxwb build --profile codex-bedrock-gw
```

### AWS CodeBuild

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
      
  build:
    commands:
      - echo Build started on `date`
      - cd guidance-for-codex-on-amazon-bedrock/source
      - poetry install
      - poetry run cxwb build --profile codex-bedrock-gw
      
  post_build:
    commands:
      - echo Build completed on `date`
```

## Best Practices

### ✅ DO

- **Use multi-arch by default** - future-proof for ARM64 adoption
- **Test on both architectures** - if you have ARM and x86 clusters
- **Monitor build times** - multi-arch adds ~2-3x build time
- **Use CI/CD** - offload builds to native architecture machines

### ❌ DON'T

- **Don't skip architecture** - always specify platform explicitly
- **Don't assume single-arch** - ECS may run on different architectures
- **Don't build locally in prod** - use CI/CD for consistency
- **Don't ignore warnings** - cross-compilation warnings indicate issues

## FAQ

**Q: Do I need multi-arch if I only use x86_64 ECS Fargate?**  
A: No, but it's recommended for future-proofing. Use `--no-multi-arch` if you want faster builds.

**Q: Will multi-arch images cost more in ECR?**  
A: Yes, ~2x storage cost (two layers instead of one), but negligible ($0.10/GB-month).

**Q: Can I build on ARM Mac and deploy to x86_64 ECS?**  
A: Yes! Multi-arch build (default) handles this automatically.

**Q: Do I need to change my ECS task definition?**  
A: No, ECS automatically pulls the correct architecture from the multi-arch manifest.

**Q: What if base image doesn't support both architectures?**  
A: Use `--no-multi-arch` and build for the architecture you need.

**Q: How do I verify what architecture was built?**  
A:
```bash
docker manifest inspect <image-uri> | jq -r '.manifests[].platform'
```

**Q: Can I build only for ARM64?**  
A: Currently no, but you can modify the build.py to add `--platform linux/arm64` support.

## References

- [Docker Buildx Documentation](https://docs.docker.com/buildx/working-with-buildx/)
- [ECR Multi-Arch Images](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-multi-architecture-image.html)
- [ECS Fargate Architecture Support](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Docker manifest-tool](https://github.com/estesp/manifest-tool)
