"""Thin wrappers around the `cfssl` CLI.

Kept intentionally thin: this module's job is only to shell out and
marshal JSON, not to reimplement any of the logic in csr.py/certinfo.py/
ledger.py -- those are what carry unit-test coverage. This module is
exercised end-to-end against a real cfssl binary as part of manual
verification instead, not mocked in the unit test suite.

Only ever called from a short-lived, explicitly-invoked CLI command
(root.py's operator flow) -- never from a long-running process (see
cli.py's module docstring). Every operation here is offline: lux's own
`cfssl ocspserve`/`ocsprefresh` are invoked directly by a systemd unit
(see hosts/lux/pki.nix), not through this package at all.
"""

from __future__ import annotations

import json
import os
import subprocess
import textwrap
from pathlib import Path


def initca(csr_request: dict) -> tuple[str, str, str]:
    """Run `cfssl genkey -initca`, returning (key_pem, csr_pem, cert_pem)."""
    result = subprocess.run(
        ["cfssl", "genkey", "-initca", "-"],
        input=json.dumps(csr_request),
        capture_output=True,
        text=True,
        check=True,
    )
    doc = json.loads(result.stdout)
    return doc["key"], doc["csr"], doc["cert"]


def gencert(
    *,
    ca: Path,
    ca_key: Path | str,
    config: Path,
    profile: str,
    db_config: Path,
    request: dict,
    extra_env: dict[str, str] | None = None,
) -> tuple[str, str]:
    """Builds a keypair + CSR + signed cert in one shot from a request
    document (no separate CSR file) -- used for every issuance now that
    there's no intermediate hop.

    `ca_key` is normally a `Path` (an on-disk key file). Pass the literal
    string `"env:VARNAME"` together with `extra_env={"VARNAME": <key
    material>}` instead to hand cfssl key material that was only ever
    decrypted into this process's memory -- confirmed via
    `cfssl gencert --help`/`cfssl sign --help`: `-ca-key` accepts
    `[file:]fname` or `env:varname`.
    """
    env = {**os.environ, **extra_env} if extra_env else None
    result = subprocess.run(
        [
            "cfssl",
            "gencert",
            "-ca",
            str(ca),
            "-ca-key",
            str(ca_key),
            "-config",
            str(config),
            "-profile",
            profile,
            "-db-config",
            str(db_config),
            "-",
        ],
        input=json.dumps(request),
        capture_output=True,
        text=True,
        check=True,
        env=env,
    )
    doc = json.loads(result.stdout)
    return doc["key"], doc["cert"]


def certinfo(cert_pem: str) -> dict:
    """`cfssl certinfo -cert -` reads the PEM from stdin directly --
    avoids a temp file just to inspect a cert we already have in memory."""
    result = subprocess.run(
        ["cfssl", "certinfo", "-cert", "-"],
        input=cert_pem,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def gencrl(*, ca: Path, ca_key: Path | str, db_config: Path, extra_env: dict[str, str] | None = None) -> str:
    """Regenerate the CRL as a PEM-wrapped string.

    `cfssl crl` (confirmed via `cfssl crl --help`) prints raw base64 on
    stdout with no PEM armor and no line-wrapping -- wrap it the same way
    the reference workflow does (`fold -w 64` + BEGIN/END X509 CRL markers).
    """
    env = {**os.environ, **extra_env} if extra_env else None
    result = subprocess.run(
        ["cfssl", "crl", "-ca", str(ca), "-ca-key", str(ca_key), "-db-config", str(db_config)],
        capture_output=True,
        text=True,
        check=True,
        env=env,
    )
    body = result.stdout.strip()
    wrapped = "\n".join(textwrap.wrap(body, 64)) if body else ""
    return f"-----BEGIN X509 CRL-----\n{wrapped}\n-----END X509 CRL-----\n"
