"""Well-known paths, resolved from the nixos repo's root.

The root is found by searching upward from the current directory for
`flake.nix` -- the one file that unambiguously marks it -- rather than
assuming cwd *is* the root. That assumption broke in practice: running
`pki` commands from inside `pki/` (a directory that itself contains real
content, easy to `cd` into by habit) silently wrote everything one level
too deep, with no error until a later command failed on a missing file
with no clear message pointing at the real cause.

Every function here is resolved lazily (called only when actually
needed), not at import time.
"""

from __future__ import annotations

import functools
from pathlib import Path


class RepoRootNotFoundError(RuntimeError):
    pass


def find_repo_root(start: Path | None = None) -> Path:
    """Search upward from `start` (default: cwd) for flake.nix."""
    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / "flake.nix").is_file():
            return candidate
    raise RepoRootNotFoundError(
        f"no flake.nix found in {current} or any parent directory -- "
        "run this from inside the nixos repo checkout (or a subdirectory of it)"
    )


@functools.lru_cache(maxsize=1)
def root() -> Path:
    return find_repo_root()


def pki_dir() -> Path:
    return root() / "pki"


def ca_cert() -> Path:
    return pki_dir() / "root-ca.pem"


def ocsp_responder_cert() -> Path:
    return pki_dir() / "ocsp-responder-cert.pem"


def ca_config() -> Path:
    return pki_dir() / "ca-config.json"


def crl() -> Path:
    return pki_dir() / "crl.pem"


# Outside noxa's host-rekey system entirely (see pki/README.md's key
# custody model) -- lives in the same private submodule as agenix
# secrets, but isn't one: nothing ever rekeys it to a host.
def external_private_pki() -> Path:
    return root() / "external" / "private" / "secrets" / "pki"


def ca_key_ciphertext() -> Path:
    return external_private_pki() / "root-ca-key.age"


def issued_certs_ledger() -> Path:
    # Private, not public `pki/` -- CN/SANs/full cert PEMs for every
    # issued cert reveal internal hostnames/topology, so this lives next
    # to the CA key in the private submodule instead.
    return external_private_pki() / "issued-certs.json"


def issued_cert(name: str) -> Path:
    # Same reasoning as issued_certs_ledger() above -- the individual
    # cert PEMs are exactly as revealing as the ledger that already
    # duplicates their content, so they live in the same place.
    return external_private_pki() / "issued" / f"{name}.pem"


def agenix_secret_path(*, host: str, module: str, ident: str) -> Path:
    """Where a `noxa.secrets.def` entry's master-encrypted raw secret
    lives -- matches `hostSecretRekeyFile` in noxa's own secrets module
    (`<secretsPath>/host/<host>/<module>/<ident>.age`). This is the file
    `agenix rekey` reads to produce the actual per-host-recipient copy
    NixOS decrypts at boot (under `external/private/secrets/rekeyed/`) --
    writing directly here (age-encrypted to the master identity, same as
    any other secret in this repo) skips the manual `agenix edit` paste
    step; `agenix rekey` still needs to run afterward to make it usable.
    """
    return root() / "external" / "private" / "secrets" / "host" / host / module / f"{ident}.age"
