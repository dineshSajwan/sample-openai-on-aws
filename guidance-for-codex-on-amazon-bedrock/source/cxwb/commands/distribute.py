"""`cxwb distribute` — build + optionally upload a developer bundle.

One bundle per deployment:
- IdC:              bundle contains the SSO config; every dev uses the same one.
- Gateway (new):    bundle contains the gateway URL + link to self-service key endpoint.
- Gateway (BYO):    same, but pointed at a pre-existing gateway.

Per-user keys are minted by the gateway (LiteLLM `/sso/key/generate` or a
platform-team equivalent). The bundle never contains a key.
"""

from __future__ import annotations

import shutil
import subprocess
import zipfile
from pathlib import Path

import boto3
import click

from .. import DEFAULT_MODEL, aws, paths, profile


def _build_idc_bundle(p: dict, outdir: Path) -> Path:
    cmd = [
        str(paths.GENERATE_IDC_BUNDLE),
        "--start-url", p["start_url"],
        "--sso-region", p["sso_region"],
        "--account-id", p["account_id"],
        "--permission-set", p["permission_set"],
        "--bedrock-region", p["bedrock_region"],
        "--profile-name", p["codex_profile_name"],
        "--model", p["model"],
        "--outdir", str(outdir),
    ]
    if p.get("otel_endpoint"):
        cmd += ["--otel-endpoint", p["otel_endpoint"]]
    click.echo(f"Running {paths.GENERATE_IDC_BUNDLE.name}...")
    subprocess.run(cmd, check=True)
    return outdir


def _gateway_endpoint_from_stack(p: dict) -> str:
    outs = aws.stack_outputs(p["region"], p["gateway_stack"])
    ep = outs.get("GatewayEndpoint")
    if not ep:
        raise click.ClickException(
            f"stack {p['gateway_stack']} has no GatewayEndpoint output — has it deployed?"
        )
    return ep


def _build_gateway_bundle(p: dict, outdir: Path) -> Path:
    if p["manages_infra"]:
        gateway_url = _gateway_endpoint_from_stack(p)
    else:
        gateway_url = p["gateway_url"]

    cmd = [
        str(paths.GENERATE_GATEWAY_BUNDLE),
        "--gateway-url", gateway_url,
        "--model", p.get("model", DEFAULT_MODEL),
        "--outdir", str(outdir),
    ]
    if p.get("key_mint_url"):
        cmd += ["--key-mint-url", p["key_mint_url"]]
    click.echo(f"Running {paths.GENERATE_GATEWAY_BUNDLE.name}...")
    subprocess.run(cmd, check=True)
    return outdir


def _zip_bundle(bundle_dir: Path) -> Path:
    zip_path = bundle_dir.with_suffix(".zip")
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in bundle_dir.rglob("*"):
            if f.is_file() and f.name != _SENTINEL:
                zf.write(f, f.relative_to(bundle_dir.parent))
    return zip_path


S3_MAX_PRESIGN = 604800  # 7 days, S3's ceiling for SigV4 presigned URLs.


def _upload_and_presign(
    zip_path: Path, bucket: str, region: str, expires: int, profile_name: str
) -> str:
    if expires > S3_MAX_PRESIGN:
        click.echo(f"  clamping --expires to S3 ceiling of {S3_MAX_PRESIGN}s")
        expires = S3_MAX_PRESIGN
    s3 = boto3.client("s3", region_name=region)
    key = f"{profile_name}/{zip_path.name}"
    click.echo(f"Uploading s3://{bucket}/{key}...")
    s3.upload_file(str(zip_path), bucket, key)
    return s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=expires,
    )


_SENTINEL = ".cxwb-bundle"


def _prepare_outdir(outdir: Path, force: bool) -> None:
    """Create (or re-create) a bundle output directory.

    Only wipes a directory we created (marked with a sentinel file) unless
    the user passes --force. Refuses to touch filesystem root or $HOME.
    """
    home = Path.home().resolve()
    dangerous = {Path("/"), home, home.parent}
    outdir = outdir.resolve()
    if outdir in dangerous or outdir.parent == outdir:
        raise click.ClickException(f"refusing to use {outdir} as an output directory")

    if outdir.exists():
        if any(outdir.iterdir()):
            if not (outdir / _SENTINEL).exists() and not force:
                raise click.ClickException(
                    f"{outdir} is not empty and was not created by cxwb. "
                    f"Pass --force to overwrite, or choose a different --outdir."
                )
            shutil.rmtree(outdir)
    outdir.mkdir(parents=True)
    (outdir / _SENTINEL).write_text("cxwb bundle output — safe to delete\n")


def run(
    profile_name: str,
    outdir: Path,
    bucket: str | None,
    expires: int,
    force: bool,
) -> None:
    p = profile.load(profile_name)
    outdir = outdir.resolve()
    _prepare_outdir(outdir, force)

    if p["auth"] == "idc":
        if not paths.GENERATE_IDC_BUNDLE.exists():
            raise click.ClickException(f"missing: {paths.GENERATE_IDC_BUNDLE}")
        _build_idc_bundle(p, outdir)
        region = p["bedrock_region"]
    elif p["auth"] == "gateway":
        if not paths.GENERATE_GATEWAY_BUNDLE.exists():
            raise click.ClickException(f"missing: {paths.GENERATE_GATEWAY_BUNDLE}")
        _build_gateway_bundle(p, outdir)
        region = p["region"]
    else:
        raise click.ClickException(f"unknown auth: {p.get('auth')!r}")

    zip_path = _zip_bundle(outdir)
    click.echo(f"Bundle: {zip_path}")

    if bucket:
        url = _upload_and_presign(zip_path, bucket, region, expires, profile_name)
        click.echo(f"\nPresigned URL (expires in {expires}s):\n{url}")
    else:
        click.echo("Skipping S3 upload (pass --bucket to enable).")
