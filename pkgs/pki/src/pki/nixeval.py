"""Draws values live from this repo's own Nix config via `nix eval`,
instead of duplicating them as hardcoded Python defaults that could
silently drift out of sync.

Run from the repo root (same assumption as repo.py). Integration-shaped
like cfssl.py/sftp.py/age.py: no unit tests invoke the real `nix` binary;
exercised as part of manual verification instead.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


def eval_json(attr: str, *, host: str = "lux") -> object:
    """Evaluate `nixosConfigurations.<host>.config.<attr>` and return its
    JSON-decoded value."""
    result = subprocess.run(
        [
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "eval",
            "--impure",
            "--no-write-lock-file",
            f".?submodules=1#nixosConfigurations.{host}.config.{attr}",
            "--json",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def domain(*, host: str = "lux") -> str:
    """This repo's `mine.info.domain` -- private (set in external/private,
    not this public repo), so it can't be hardcoded here either. Used to
    embed the real AIA (crl_url/ocsp_url/issuer_urls) into every cert
    this tool signs -- see cli.py's `_config_with_pki_urls`.
    """
    value = eval_json("mine.info.domain", host=host)
    if not value:
        raise ValueError(f"mine.info.domain is unset for host {host!r} -- can't embed AIA/CRL URLs")
    return value


def master_identity(*, host: str = "lux") -> tuple[Path, str]:
    """Return (identity_path, pubkey) for the first entry of
    nixos/secrets.nix's `noxa.secrets.options.masterIdentities`, drawn
    live rather than hardcoded -- so the root CA key always uses whatever
    identity this repo's own secrets are actually rekeyed to, even if
    that identity is later rotated.
    """
    identities = eval_json("noxa.secrets.options.masterIdentities", host=host)
    if not identities:
        raise ValueError(
            "nixos/secrets.nix's noxa.secrets.options.masterIdentities is empty -- "
            "nothing to draw a default identity/recipient from"
        )
    first = identities[0]
    return Path(first["identity"]), first["pubkey"]
