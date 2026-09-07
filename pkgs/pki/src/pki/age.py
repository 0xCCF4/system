"""Thin wrapper around the `age` CLI, used only for the root CA key.

The root key is the one piece of key material this tool ever writes to
disk at rest (everywhere else -- the intermediate and OCSP-responder
keys -- goes through agenix instead, see hosts/lux/pki.nix). It's never
written in plaintext: `root.init()` encrypts it the moment it's
generated, and `root.sign_intermediate()` decrypts it only into memory
(and the `cfssl` subprocess's environment, via `-ca-key env:...` --
never a plaintext file) for the duration of a single signing call.

Integration-shaped like cfssl.py/sftp.py: no unit tests call the real
`age` binary; exercised end-to-end as part of manual verification
instead.
"""

from __future__ import annotations

import subprocess
from pathlib import Path


def encrypt(*, recipients: list[str], plaintext: str) -> bytes:
    """Encrypt `plaintext` to every recipient in `recipients` (each an age
    public key or an ssh public key, anything `age -r` accepts), returning
    the encrypted bytes.

    Raises ValueError for an empty recipient list -- `age` invoked with no
    `-r` at all doesn't error the way you'd want here (it can read
    recipients from stdin instead), so this is caught explicitly rather
    than risk silently encrypting to nobody.
    """
    if not recipients:
        raise ValueError("encrypt() requires at least one recipient")
    args = ["age"]
    for recipient in recipients:
        args += ["-r", recipient]
    result = subprocess.run(args, input=plaintext.encode(), capture_output=True, check=True)
    return result.stdout


def decrypt(*, identity: Path, ciphertext_path: Path) -> str:
    """Decrypt an age-encrypted file with `identity` (a private key file
    -- age or ssh format, anything `age -i` accepts), returning the
    plaintext as a string.

    Callers must not write the return value to disk -- pass it to
    whatever needs it (e.g. cfssl.sign's `extra_env`) directly instead.
    """
    result = subprocess.run(
        ["age", "-d", "-i", str(identity), str(ciphertext_path)],
        capture_output=True,
        check=True,
    )
    return result.stdout.decode()
