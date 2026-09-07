"""The only module that ever touches the CA key. Every function here runs
off-host, by whoever holds it -- never on lux, never automated.

The CA key is never written to disk in plaintext, not even transiently:
`init()` encrypts it with `age` the moment `cfssl` produces it and only
ever returns the ciphertext; `issue()`/`gencrl()` decrypt it straight into
this process's memory and hand it to `cfssl` via an environment variable
(`-ca-key env:...`), never a file.

There's no intermediate anymore -- every leaf cert (and the OCSP
responder cert) is signed directly by this one key, in one step
(`cfssl gencert`, key+CSR+signing all at once) instead of the old
two-hop root-signs-intermediate-signs-leaf flow.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from . import age as age_mod
from . import cfssl

_CA_KEY_ENV_VAR = "PKI_CA_KEY"


@dataclass(frozen=True)
class InitResult:
    ca_key_ciphertext: bytes  # age-encrypted -- the plaintext never leaves init()
    ca_cert_pem: str


def init(*, ca_request: dict, recipients: list[str]) -> InitResult:
    """Bootstrap: self-sign the CA, encrypt its key to `recipients`
    immediately."""
    ca_key_pem, _csr_pem, ca_cert_pem = cfssl.initca(ca_request)
    ca_key_ciphertext = age_mod.encrypt(recipients=recipients, plaintext=ca_key_pem)
    return InitResult(ca_key_ciphertext=ca_key_ciphertext, ca_cert_pem=ca_cert_pem)


def _decrypt_ca_key(*, ca_key_ciphertext: Path, identity: Path) -> tuple[str, dict[str, str]]:
    """Returns (ca_key_arg, extra_env) ready to splice into a cfssl.* call
    -- decrypts once, holds the plaintext only in this process's memory
    and the child cfssl subprocess's environment."""
    ca_key_pem = age_mod.decrypt(identity=identity, ciphertext_path=ca_key_ciphertext)
    return f"env:{_CA_KEY_ENV_VAR}", {_CA_KEY_ENV_VAR: ca_key_pem}


def issue(
    *,
    request: dict,
    profile: str,
    ca: Path,
    ca_key_ciphertext: Path,
    identity: Path,
    config: Path,
    db_config: Path,
) -> tuple[str, str]:
    """Issue a new keypair + cert directly under `profile`. Returns
    (key_pem, cert_pem). Used both for ordinary leaf certs and the OCSP
    responder cert -- the only difference is which profile/request is
    passed in.
    """
    ca_key_arg, extra_env = _decrypt_ca_key(ca_key_ciphertext=ca_key_ciphertext, identity=identity)
    return cfssl.gencert(
        ca=ca,
        ca_key=ca_key_arg,
        config=config,
        profile=profile,
        db_config=db_config,
        request=request,
        extra_env=extra_env,
    )


def gencrl(*, ca: Path, ca_key_ciphertext: Path, identity: Path, db_config: Path) -> str:
    """Regenerate the CRL from whatever's in `db_config` (built from the
    ledger just before this is called -- see cli.py). Still needs the CA
    key transiently: cfssl has no delegated CRL-signer the way it does
    for OCSP (confirmed via `cfssl crl --help`: only `-ca`/`-ca-key`, no
    responder-key equivalent)."""
    ca_key_arg, extra_env = _decrypt_ca_key(ca_key_ciphertext=ca_key_ciphertext, identity=identity)
    return cfssl.gencrl(ca=ca, ca_key=ca_key_arg, db_config=db_config, extra_env=extra_env)
