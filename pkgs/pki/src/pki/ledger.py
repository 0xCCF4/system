"""The cert-issuance ledger: a plain, human-reviewable, git-diffable JSON
file (pki/issued-certs.json) that's the single source of truth for what's
been issued and revoked -- replacing cfssl's own sqlite db as *committed*
state. cfssl itself still needs a real sqlite db to do its job (`sign`/
`gencert`/`crl`/`ocsprefresh` all take `-db-config`), so `to_sqlite()`
builds one on demand from this ledger; nothing sqlite-shaped is ever
committed.

The exact row encoding below (date format, AKI hex normalization, the
Go-zero-value `revoked_at`, the literal string `"null"` for `metadata`,
`ca_label` and `reason` never NULL) is not guessed -- it was verified
against a real cfssl binary: populate a schema-only db by hand, then
confirm `cfssl ocsprefresh`/`ocspserve`/`crl` all read it correctly
end-to-end (including a live `openssl ocsp` query resolving "Cert Status:
good"). Get any of these wrong and cfssl's Go sql scanner errors on NULL
columns it expects to be populated, or `ocsprefresh`/`ocspserve` silently
can't find the row at all.
"""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

_SCHEMA = """
CREATE TABLE certificates (
  serial_number blob NOT NULL, authority_key_identifier blob NOT NULL,
  ca_label blob, status blob NOT NULL, reason int, expiry timestamp,
  revoked_at timestamp, pem blob NOT NULL, issued_at timestamp,
  not_before timestamp, metadata text, sans text, common_name text,
  PRIMARY KEY(serial_number, authority_key_identifier)
);
CREATE TABLE ocsp_responses (
  serial_number blob NOT NULL, authority_key_identifier blob NOT NULL,
  body blob NOT NULL, expiry timestamp,
  PRIMARY KEY(serial_number, authority_key_identifier),
  FOREIGN KEY(serial_number, authority_key_identifier)
    REFERENCES certificates(serial_number, authority_key_identifier)
);
"""

# Go's zero-value time.Time -- what cfssl itself writes for revoked_at on a
# cert that's never been revoked (confirmed against a real cfssl-inserted
# row); using anything else (including NULL) breaks ocsprefresh's sql scan.
_GO_ZERO_TIME = "0001-01-01 00:00:00+00:00"

# RFC 5280 §5.3.1 CRLReason (value 7 is reserved/unused).
REVOCATION_REASONS = {
    "unspecified": 0,
    "keycompromise": 1,
    "cacompromise": 2,
    "affiliationchanged": 3,
    "superseded": 4,
    "cessationofoperation": 5,
    "certificatehold": 6,
    "removefromcrl": 8,
    "privilegewithdrawn": 9,
    "aacompromise": 10,
}


def _cfssl_timestamp(certinfo_timestamp: str) -> str:
    """cfssl's certinfo gives "2026-12-07T23:30:00Z"; its own sqlite rows
    store "2026-12-07 23:30:00+00:00" -- confirmed these are the only two
    shapes involved (both always UTC, always this precision)."""
    dt = datetime.strptime(certinfo_timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:%S+00:00")


def normalize_authority_key_id(certinfo_aki: str) -> str:
    """certinfo gives "65:56:EC:45:..."; cfssl's own rows store
    "6556ec45..." (lowercase, no colons) -- confirmed against a real
    cfssl-inserted row."""
    return certinfo_aki.replace(":", "").lower()


def load(path: Path) -> dict:
    if not path.exists():
        return {"certs": {}}
    return json.loads(path.read_text())


def save(path: Path, ledger: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n")


def record_issued(
    ledger: dict,
    *,
    name: str,
    cn: str,
    sans: list[str],
    profile: str,
    serial: str,
    authority_key_id: str,
    not_before: str,
    not_after: str,
    pem: str,
) -> dict:
    """`serial`/`authority_key_id`/`not_before`/`not_after` are exactly
    what `cfssl certinfo -cert` reports (raw, not yet normalized) --
    normalization happens once, in `to_sqlite`, not here, so the ledger
    itself stays a faithful, human-readable record of what certinfo
    actually said.
    """
    ledger.setdefault("certs", {})[name] = {
        "cn": cn,
        "sans": sans,
        "profile": profile,
        "serial": serial,
        "authority_key_id": authority_key_id,
        "not_before": not_before,
        "not_after": not_after,
        "pem": pem,
        "revoked": False,
        "revoked_at": None,
        "reason": None,
    }
    return ledger


def mark_revoked(ledger: dict, name: str, reason: str = "unspecified") -> dict:
    if reason not in REVOCATION_REASONS:
        raise ValueError(f"unknown revocation reason {reason!r}, expected one of {sorted(REVOCATION_REASONS)}")
    certs = ledger.get("certs", {})
    if name not in certs:
        raise KeyError(f"{name!r} is not in the ledger -- nothing to revoke")
    certs[name]["revoked"] = True
    certs[name]["revoked_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    certs[name]["reason"] = reason
    return ledger


def to_sqlite(ledger: dict, sqlite_path: Path) -> None:
    """Build a fresh cfssl-schema sqlite DB from the ledger. Always
    starts clean (overwrites any existing file) -- this is meant to be
    regenerated on demand (by the admin locally, or by Nix at build time
    for lux's deployed copy), never edited in place.
    """
    sqlite_path.parent.mkdir(parents=True, exist_ok=True)
    sqlite_path.unlink(missing_ok=True)
    conn = sqlite3.connect(sqlite_path)
    try:
        conn.executescript(_SCHEMA)
        for entry in ledger.get("certs", {}).values():
            revoked = entry["revoked"]
            conn.execute(
                "INSERT INTO certificates ("
                "serial_number, authority_key_identifier, ca_label, status, reason, "
                "expiry, revoked_at, not_before, pem, metadata, common_name, sans"
                ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    entry["serial"],
                    normalize_authority_key_id(entry["authority_key_id"]),
                    "",  # ca_label: never NULL, cfssl's own rows leave it empty
                    "revoked" if revoked else "good",
                    REVOCATION_REASONS[entry["reason"]] if revoked else 0,
                    _cfssl_timestamp(entry["not_after"]),
                    _cfssl_timestamp(entry["revoked_at"]) if revoked else _GO_ZERO_TIME,
                    _cfssl_timestamp(entry["not_before"]),
                    entry["pem"],
                    "null",  # metadata: never NULL either -- cfssl's own rows store the literal string "null"
                    entry["cn"],
                    json.dumps(entry["sans"]),
                ),
            )
        conn.commit()
    finally:
        conn.close()


def write_db_config(db_config_path: Path, sqlite_path: Path) -> None:
    db_config_path.parent.mkdir(parents=True, exist_ok=True)
    db_config_path.write_text(json.dumps({"driver": "sqlite3", "data_source": str(sqlite_path)}))
