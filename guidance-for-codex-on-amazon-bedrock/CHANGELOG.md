# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-15

### Added
- Initial release of Guidance for Codex with Amazon Bedrock
- `cxwb` wizard covering four deployment shapes: IdC deploy / IdC BYO / LiteLLM Gateway deploy / Gateway BYO
- Gateway developer bundle generator (`generate-codex-gateway-config.sh`) — bundles never contain keys; developers self-serve via the gateway's SSO endpoint
- Enterprise deployment patterns for OpenAI Codex CLI with Amazon Bedrock
- OIDC-based identity provider integration (Auth0, Azure AD, Cognito, Okta)
- Cross-region inference support via Amazon Bedrock CRIS profiles
- Monitoring dashboard with CloudWatch metrics and analytics pipeline
- Quota management per user and group
- Multi-platform credential process binaries (macOS arm64/intel, Linux, Windows)
- GovCloud (us-gov-west-1, us-gov-east-1) support
