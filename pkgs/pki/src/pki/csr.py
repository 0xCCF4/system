"""Construction of cfssl CSR-request JSON documents.

This only builds the JSON document `cfssl genkey -initca`/`gencert` read
on stdin -- it never talks to cfssl itself (see cfssl.py for that).
"""

from __future__ import annotations

from dataclasses import dataclass

DEFAULT_KEY_ALGO = "ecdsa"
DEFAULT_KEY_SIZE = 256


@dataclass(frozen=True)
class OrgNames:
    country: str = ""
    state: str = ""
    locality: str = ""
    organization: str = ""


DEFAULT_ORG = OrgNames()


def build_csr_request(
    *,
    cn: str,
    sans: list[str] | None = None,
    org: OrgNames = DEFAULT_ORG,
    key_algo: str = DEFAULT_KEY_ALGO,
    key_size: int = DEFAULT_KEY_SIZE,
) -> dict:
    """Build the JSON document `cfssl genkey`/`cfssl gencsr` expect on stdin."""
    if not cn:
        raise ValueError("CN must not be empty")
    return {
        "CN": cn,
        "hosts": list(sans or []),
        "key": {"algo": key_algo, "size": key_size},
        "names": [
            {
                "C": org.country,
                "ST": org.state,
                "L": org.locality,
                "O": org.organization,
            }
        ],
    }
