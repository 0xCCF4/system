"""Parsing of `cfssl certinfo` JSON output for `pki status`."""

from __future__ import annotations

from datetime import datetime, timezone

# cfssl certinfo emits timestamps like "2027-01-02T03:04:05Z"
_CFSSL_TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


def parse_not_after(certinfo: dict) -> datetime:
    raw = certinfo.get("not_after")
    if not raw:
        raise ValueError("certinfo output has no 'not_after' field")
    return datetime.strptime(raw, _CFSSL_TIME_FORMAT).replace(tzinfo=timezone.utc)


def days_until_expiry(certinfo: dict, *, now: datetime | None = None) -> int:
    expiry = parse_not_after(certinfo)
    now = now or datetime.now(timezone.utc)
    return (expiry - now).days
