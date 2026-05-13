"""`cxwb destroy` — tear down stacks created by the active profile."""

from __future__ import annotations

import click

from .. import aws, profile
from .status import stacks_for


def run(profile_name: str, yes: bool) -> None:
    p = profile.load(profile_name)
    region, stacks = stacks_for(p)
    if not stacks:
        click.echo("External gateway — nothing to destroy.")
        return
    click.echo(f"Will delete in {region}:")
    for s in stacks:
        click.echo(f"  - {s}")
    if not yes and not click.confirm("Proceed?", default=False):
        raise click.Abort()
    # Delete in reverse order (gateway before otel before networking).
    for name in reversed(stacks):
        aws.delete_stack(region, name)
