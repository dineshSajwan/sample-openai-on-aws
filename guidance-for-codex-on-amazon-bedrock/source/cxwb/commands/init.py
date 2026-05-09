"""`cxwb init` — interactive profile wizard for IdC or Gateway."""

from __future__ import annotations

import re

import click
import questionary

from .. import DEFAULT_MODEL, profile

BEDROCK_REGIONS = ["us-east-1", "us-east-2", "us-west-2"]


def _text(prompt: str, default: str = "", validate=None) -> str:
    answer = questionary.text(prompt, default=default, validate=validate).ask()
    if answer is None:
        raise click.Abort()
    return answer.strip()


def _select(prompt: str, choices: list[str], default: str | None = None) -> str:
    answer = questionary.select(prompt, choices=choices, default=default).ask()
    if answer is None:
        raise click.Abort()
    return answer


def _confirm(prompt: str, default: bool = False) -> bool:
    answer = questionary.confirm(prompt, default=default).ask()
    if answer is None:
        raise click.Abort()
    return answer


def _idc_common() -> dict:
    return {
        "start_url": _text(
            "IdC start URL (e.g. https://d-xxxxxxxxxx.awsapps.com/start):",
            validate=lambda v: v.startswith("https://") or "must start with https://",
        ),
        "sso_region": _text("IdC home region (e.g. us-east-1):", default="us-east-1"),
        "account_id": _text(
            "AWS account ID holding the Bedrock role:",
            validate=lambda v: bool(re.fullmatch(r"\d{12}", v)) or "12 digits",
        ),
        "permission_set": _text("Permission set name:", default="CodexBedrockUser"),
        "bedrock_region": _select(
            "Bedrock region:", BEDROCK_REGIONS, default="us-west-2"
        ),
        "model": _text("Default Codex model:", default=DEFAULT_MODEL),
        "codex_profile_name": _text(
            "Codex profile name (written into ~/.codex/config.toml):",
            default="codex",
        ),
        "otel_endpoint": _text(
            "OTel endpoint (optional, leave blank to skip):", default=""
        ),
    }


def _idc_flow() -> dict:
    click.echo("\nIAM Identity Center — deploy Bedrock role + policy.\n")
    return {
        "auth": "idc",
        "manages_infra": True,
        "stack_name": _text("CloudFormation stack name:", default="codex-bedrock-idc"),
        **_idc_common(),
    }


def _existing_idc_flow() -> dict:
    click.echo("\nExisting IdC deployment — bundle-only.\n")
    click.echo(
        "Assumes you already have: a Bedrock-invoke IAM role trusted by "
        "sso.amazonaws.com and attached to a permission set in your IdC instance.\n"
    )
    return {
        "auth": "idc",
        "manages_infra": False,
        **_idc_common(),
    }


def _existing_gateway_flow() -> dict:
    click.echo("\nExisting gateway — no deploy, distribute only.\n")
    return {
        "auth": "gateway",
        "manages_infra": False,
        "gateway_url": _text(
            "Gateway base URL (include /v1, e.g. https://gw.example.com/v1):",
            validate=lambda v: v.startswith(("http://", "https://")) or "must be an http(s) URL",
        ),
        "key_mint_url": _text(
            "Self-service key endpoint (optional, leave blank if you hand out keys manually):",
            default="",
        ),
        "model": _text("Default model alias on this gateway:", default=DEFAULT_MODEL),
        "region": _select(
            "AWS region for S3 bundle uploads:", BEDROCK_REGIONS, default="us-west-2"
        ),
    }


def _gateway_flow() -> dict:
    click.echo("\nLiteLLM Gateway path.\n")
    data: dict = {
        "auth": "gateway",
        "manages_infra": True,
        "region": _select(
            "AWS region for the gateway:", BEDROCK_REGIONS, default="us-west-2"
        ),
        "networking_stack": _text(
            "Networking stack name:", default="codex-otel-networking"
        ),
        "otel_stack": _text("OTel stack name:", default="codex-otel-collector"),
        "gateway_stack": _text("Gateway stack name:", default="codex-litellm-gateway"),
        "image_uri": _text(
            "LiteLLM container image URI (ECR repo:tag):",
            validate=lambda v: "/" in v or "must include a repository path",
        ),
        "allowed_cidr": _text(
            "CIDR allowed to reach the ALB:", default="10.0.0.0/16"
        ),
        "key_mint_url": _text(
            "Self-service key endpoint (optional, e.g. https://gw/sso/key/generate):",
            default="",
        ),
        "model": _text("Default model alias:", default=DEFAULT_MODEL),
    }
    if _confirm("Generate a random LiteLLM master key and DB password now?", True):
        import secrets

        data["master_key"] = "sk-" + secrets.token_hex(16)
        data["db_password"] = secrets.token_hex(16)
    else:
        data["master_key"] = _text("LiteLLM master key (sk-...):")
        data["db_password"] = _text("RDS master password:")
    return data


def run() -> None:
    click.echo("cxwb init — configure a deployment profile.\n")
    choice = _select(
        "Deployment path:",
        choices=[
            "IAM Identity Center — deploy new (recommended)",
            "IAM Identity Center — existing (BYO role + permission set)",
            "LiteLLM Gateway — deploy new",
            "Gateway — existing (BYO LiteLLM / Portkey / Kong AI / ...)",
        ],
    )
    flows = {
        "IAM Identity Center — deploy new (recommended)": _idc_flow,
        "IAM Identity Center — existing (BYO role + permission set)": _existing_idc_flow,
        "LiteLLM Gateway — deploy new": _gateway_flow,
        "Gateway — existing (BYO LiteLLM / Portkey / Kong AI / ...)": _existing_gateway_flow,
    }
    data = flows[choice]()

    name = _text("\nProfile name:", default="default")
    saved = profile.save(name, data)
    click.echo(f"\nSaved profile to {saved}")
    if data["manages_infra"]:
        click.echo(f"Next: cxwb deploy --profile {name}")
    else:
        click.echo(f"Next: cxwb distribute --profile {name} --bucket <bucket>")
