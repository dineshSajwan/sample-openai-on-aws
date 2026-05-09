"""`cxwb deploy` — create/update CloudFormation stacks for the active profile."""

from __future__ import annotations

import click

from .. import aws, paths, profile


def _deploy_idc(p: dict) -> None:
    region = p["bedrock_region"]
    click.echo(f"Deploying IdC Bedrock auth stack in {region}...")
    outputs = aws.deploy_stack(
        region=region,
        name=p["stack_name"],
        template=paths.IDC_TEMPLATE,
        parameters={},
        capabilities=["CAPABILITY_NAMED_IAM"],
    )
    click.echo("\nStack outputs:")
    for k, v in outputs.items():
        click.echo(f"  {k} = {v}")
    click.echo(
        "\nNext: attach the customer-managed policy to your `"
        f"{p['permission_set']}` permission set in IAM Identity Center, then run:"
        f"\n  cxwb distribute --profile <profile>"
    )


def _deploy_gateway(p: dict) -> None:
    region = p["region"]
    click.echo(f"Deploying networking stack in {region}...")
    aws.deploy_stack(
        region=region,
        name=p["networking_stack"],
        template=paths.NETWORKING_TEMPLATE,
        parameters={},
        capabilities=["CAPABILITY_IAM"],
    )

    click.echo("\nDeploying OTel collector stack...")
    net_outputs = aws.stack_outputs(region, p["networking_stack"])
    aws.deploy_stack(
        region=region,
        name=p["otel_stack"],
        template=paths.OTEL_TEMPLATE,
        parameters={
            "VpcId": net_outputs["VpcId"],
            "SubnetIds": net_outputs["SubnetIds"],
        },
        capabilities=["CAPABILITY_IAM"],
    )

    click.echo("\nDeploying LiteLLM gateway stack...")
    outputs = aws.deploy_stack(
        region=region,
        name=p["gateway_stack"],
        template=paths.LITELLM_TEMPLATE,
        parameters={
            "NetworkingStackName": p["networking_stack"],
            "OtelStackName": p["otel_stack"],
            "AwsRegion": region,
            "LiteLLMImage": p["image_uri"],
            "LiteLLMMasterKey": p["master_key"],
            "DBPassword": p["db_password"],
            "AllowedCidr": p["allowed_cidr"],
        },
        capabilities=["CAPABILITY_IAM"],
    )
    click.echo("\nGateway outputs:")
    for k, v in outputs.items():
        click.echo(f"  {k} = {v}")


def run(profile_name: str) -> None:
    p = profile.load(profile_name)
    if not p["manages_infra"]:
        click.echo(
            "Profile does not manage infrastructure — nothing to deploy. "
            "Run `cxwb distribute` to produce the bundle."
        )
        return
    if p["auth"] == "idc":
        _deploy_idc(p)
    elif p["auth"] == "gateway":
        _deploy_gateway(p)
    else:
        raise click.ClickException(f"unknown auth in profile: {p.get('auth')!r}")
