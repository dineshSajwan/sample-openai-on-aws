"""Thin boto3 wrappers for CloudFormation operations."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

import boto3
import click
from botocore.exceptions import ClientError, WaiterError

TERMINAL_STATES = {
    "CREATE_COMPLETE",
    "UPDATE_COMPLETE",
    "CREATE_FAILED",
    "ROLLBACK_COMPLETE",
    "UPDATE_ROLLBACK_COMPLETE",
    "DELETE_COMPLETE",
    "DELETE_FAILED",
}


def cfn(region: str):
    return boto3.client("cloudformation", region_name=region)


def stack_exists(region: str, name: str) -> str | None:
    try:
        resp = cfn(region).describe_stacks(StackName=name)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        msg = e.response.get("Error", {}).get("Message", "")
        if code == "ValidationError" and "does not exist" in msg:
            return None
        raise
    return resp["Stacks"][0]["StackStatus"]


def stack_outputs(region: str, name: str) -> dict[str, str]:
    resp = cfn(region).describe_stacks(StackName=name)
    outputs = resp["Stacks"][0].get("Outputs") or []
    return {o["OutputKey"]: o["OutputValue"] for o in outputs}


def deploy_stack(
    region: str,
    name: str,
    template: Path,
    parameters: dict[str, str],
    capabilities: list[str] | None = None,
) -> dict[str, Any]:
    """Create-or-update a stack, wait for completion, return Outputs dict."""
    client = cfn(region)
    params = [{"ParameterKey": k, "ParameterValue": v} for k, v in parameters.items()]
    kwargs = {
        "StackName": name,
        "TemplateBody": template.read_text(),
        "Parameters": params,
        "Capabilities": capabilities or [],
    }

    existing = stack_exists(region, name)
    try:
        if existing is None:
            client.create_stack(**kwargs)
            waiter = client.get_waiter("stack_create_complete")
        else:
            client.update_stack(**kwargs)
            waiter = client.get_waiter("stack_update_complete")
    except ClientError as e:
        msg = e.response.get("Error", {}).get("Message", "")
        if "No updates are to be performed" in msg:
            click.echo(f"  no changes to {name}")
            return stack_outputs(region, name)
        raise

    click.echo(f"  waiting on {name}...")
    try:
        waiter.wait(StackName=name, WaiterConfig={"Delay": 15, "MaxAttempts": 160})
    except WaiterError as e:
        _print_recent_failures(client, name)
        raise click.ClickException(f"stack {name} failed: {e}")
    return stack_outputs(region, name)


def _print_recent_failures(client, name: str) -> None:
    """Dump the last few FAILED stack events to help diagnose waiter failures."""
    try:
        events = client.describe_stack_events(StackName=name)["StackEvents"]
    except ClientError:
        return
    failed = [e for e in events if e.get("ResourceStatus", "").endswith("FAILED")]
    if not failed:
        return
    click.echo(f"\n  Recent failures in {name}:")
    for e in failed[:5]:
        click.echo(
            f"    {e['LogicalResourceId']} ({e['ResourceStatus']}): "
            f"{e.get('ResourceStatusReason', 'no reason')}"
        )


def delete_stack(region: str, name: str) -> None:
    client = cfn(region)
    if stack_exists(region, name) is None:
        click.echo(f"  {name} does not exist")
        return
    client.delete_stack(StackName=name)
    click.echo(f"  waiting on delete of {name}...")
    waiter = client.get_waiter("stack_delete_complete")
    try:
        waiter.wait(StackName=name, WaiterConfig={"Delay": 15, "MaxAttempts": 160})
    except WaiterError as e:
        raise click.ClickException(f"delete of {name} failed: {e}")


def poll_until_done(region: str, name: str, interval: int = 10) -> str:
    """For status command: poll until stack reaches a terminal state."""
    client = cfn(region)
    while True:
        status = stack_exists(region, name)
        if status is None:
            return "DOES_NOT_EXIST"
        if status in TERMINAL_STATES:
            return status
        click.echo(f"  {name}: {status}")
        time.sleep(interval)
