# Sample-OpenAI-on-AWS

Welcome to the Sample OpenAI-on-AWS repository! This repository provides production-ready deployment guidance for running OpenAI Codex on Amazon Bedrock at enterprise scale—with corporate SSO, quota enforcement, and observability built-in. You'll also find practical notebooks and examples for experimenting with GPT-OSS models on AWS infrastructure.

![repo-image](base-imgs/OpenAI-AWS.png)

---

## 🏢 Guidance for Codex on Amazon Bedrock

**Enterprise-ready deployment patterns for OpenAI Codex with Amazon Bedrock**

This guidance provides three production-ready deployment patterns for running OpenAI Codex at enterprise scale with corporate SSO, quota enforcement, and comprehensive observability.

### What This Guidance Provides

- Corporate SSO integration (Okta, Azure AD, Auth0, AWS IAM Identity Center)
- No API keys or static credentials to manage
- Per-user CloudTrail audit trails for compliance
- Hard quota enforcement with request blocking (Pattern 2/3)
- Per-user and per-team budget limits with rate limiting
- Real-time CloudWatch dashboards (token usage, latency, errors)
- Long-term data lake for historical analysis (Pattern 3)
- Productivity analytics and ROI reporting (Pattern 3)
- One-command authentication (`aws sso login` or API key)
- Cross-platform support (Windows, macOS, Linux)

### Choose Your Pattern

```text
Need hard quota enforcement? (Block requests when limits hit)
│
├── YES → Pattern 2 or 3 (Gateway required)
│         │
│         └── Need ROI reporting?
│              ├── No  → Pattern 2: Governed Gateway
│              └── Yes → Pattern 3: Full Observability
│
└── NO → Already use AWS IAM Identity Center?
          │
          ├── YES → Pattern 1: Native AWS Access
          │
          └── NO → Choose:
                    Pattern 1 (set up IdC) OR Pattern 2 (gateway)
```

### Pattern Comparison

| Pattern | Setup Time | Best For |
| ------- | ---------- | -------- |
| **[Pattern 1: Native AWS Access](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN1.md)** | 5-60 min | Teams with IdC, soft monitoring OK |
| **[Pattern 2: Governed Gateway](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN2.md)** | 15 min | Hard budgets, rate limiting |
| **[Pattern 3: Full Observability](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN3.md)** | +30 min | ROI reporting, analytics |

### Quick Start

```bash
# Clone repository
git clone https://github.com/aws-samples/sample-openai-on-aws.git
cd sample-openai-on-aws/guidance-for-codex-on-amazon-bedrock

# Install wizard
cd source/ && uv sync

# Run guided deployment (choose your pattern below)
uv run cxwb init     # Choose pattern and answer prompts
uv run cxwb deploy   # Deploy infrastructure
uv run cxwb distribute --bucket my-bucket  # Generate developer bundle
```

**After running `cxwb init`, follow the guide for your chosen pattern:**

- **Pattern 1 chosen?** → [Native AWS Access Quickstart](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN1.md)
- **Pattern 2 chosen?** → [Governed Gateway Quickstart](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN2.md)
- **Pattern 3 chosen?** → [Full Observability Quickstart](guidance-for-codex-on-amazon-bedrock/QUICKSTART_PATTERN3.md)

### Documentation

**→ [Complete Guidance Documentation](guidance-for-codex-on-amazon-bedrock/README.md)** — Overview, decision tree, pattern details

**Technical Documentation:**

- [Architecture & Deployment](guidance-for-codex-on-amazon-bedrock/docs/01-decide.md) — Detailed pattern comparison
- [Monitoring & Operations](guidance-for-codex-on-amazon-bedrock/docs/operate-monitoring.md) — CloudWatch dashboards, OTel setup
- [Troubleshooting](guidance-for-codex-on-amazon-bedrock/docs/operate-troubleshooting.md) — Common issues and fixes

---

## 🚀 Getting Started

Start with our foundational notebooks:

- [Getting Started with GPT-OSS models on Bedrock](https://github.com/aws-samples/sample-openai-on-aws/blob/main/Bedrock/Getting_Started_Guide_Bedrock.ipynb) 🧠 
Walks through using GPT-OSS models on Amazon Bedrock with both the Converse and InvokeModel APIs. It also shows how to instantiate and call these models via the OpenAI Chat Completions API, and explains how those calls map to Bedrock's InvokeModel payloads

- [Deploying GPT-OSS models as Inference Components on SageMaker](https://github.com/aws-samples/sample-openai-on-aws/blob/main/SageMaker/Inference/OpenAI-OSS-IC-EXA-sample.ipynb) 🪼
Demonstrates deploying the GPT-OSS models on Amazon SageMaker JumpStart using Inference Components (ICs). ICs let you host multiple copies of a model—or different models—behind a single endpoint and route traffic to specific components. We also provide a deep dive on the Harmony training/formatting schema, show built-in tool use with Exa, and illustrate how to integrate external functions with this format.

- [Use OpenAI OSS models on Amazon Bedrock with LangChain](https://github.com/aws-samples/sample-openai-on-aws/blob/main/Bedrock/agentic_workflow_with_langchain.ipynb)
In this notebook, you learn how you can use OpenAI OSS models from Bedrock with Langchain.

---

## 🤝 Contributing

We're actively looking for contributors! Whether you're interested in:

- Adding new examples and tutorials
- Improving existing notebooks
- Documentation enhancements
- Bug fixes and optimizations
- Sharing your own use cases

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
