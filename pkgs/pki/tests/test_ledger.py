import json
import sqlite3
from pathlib import Path

import pytest

from pki import ledger


def test_normalize_authority_key_id():
    assert ledger.normalize_authority_key_id("65:56:EC:45:D3:CE") == "6556ec45d3ce"


def test_cfssl_timestamp_conversion():
    assert ledger._cfssl_timestamp("2026-12-07T23:30:00Z") == "2026-12-07 23:30:00+00:00"


def test_record_issued_and_load_roundtrip(tmp_path: Path):
    path = tmp_path / "issued-certs.json"
    data = ledger.load(path)
    ledger.record_issued(
        data,
        name="lux-ocsp",
        cn="lux OCSP Responder",
        sans=[],
        profile="ocsp",
        serial="12345",
        authority_key_id="AA:BB:CC",
        not_before="2026-01-01T00:00:00Z",
        not_after="2027-01-01T00:00:00Z",
        pem="-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----\n",
    )
    ledger.save(path, data)

    reloaded = ledger.load(path)
    entry = reloaded["certs"]["lux-ocsp"]
    assert entry["cn"] == "lux OCSP Responder"
    assert entry["serial"] == "12345"
    assert entry["revoked"] is False
    assert entry["revoked_at"] is None


def test_load_missing_file_returns_empty_ledger(tmp_path: Path):
    assert ledger.load(tmp_path / "nonexistent.json") == {"certs": {}}


def test_mark_revoked(tmp_path: Path):
    data = {"certs": {}}
    ledger.record_issued(
        data, name="x", cn="x", sans=[], profile="server", serial="1",
        authority_key_id="AA", not_before="2026-01-01T00:00:00Z",
        not_after="2027-01-01T00:00:00Z", pem="PEM",
    )
    ledger.mark_revoked(data, "x", reason="keycompromise")
    entry = data["certs"]["x"]
    assert entry["revoked"] is True
    assert entry["reason"] == "keycompromise"
    assert entry["revoked_at"] is not None


def test_mark_revoked_unknown_name_raises(tmp_path: Path):
    with pytest.raises(KeyError):
        ledger.mark_revoked({"certs": {}}, "nonexistent")


def test_mark_revoked_unknown_reason_raises():
    data = {"certs": {"x": {}}}
    with pytest.raises(ValueError):
        ledger.mark_revoked(data, "x", reason="not-a-real-reason")


def test_to_sqlite_produces_verified_row_format(tmp_path: Path):
    # These exact values/formats were confirmed against a real cfssl
    # binary (see the module docstring) -- this test locks in the
    # regression, not just "some sqlite file gets created".
    data = {"certs": {}}
    ledger.record_issued(
        data,
        name="leaf",
        cn="leaf.example",
        sans=["leaf.example"],
        profile="server",
        serial="53494052835944942516701023896819511076934191012",
        authority_key_id="65:56:EC:45:D3:CE:4D:85:A7:15:1D:67:91:EC:5A:31:37:47:42:5A",
        not_before="2026-09-07T17:30:00Z",
        not_after="2026-12-07T23:30:00Z",
        pem="-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----\n",
    )
    sqlite_path = tmp_path / "certstore.db"
    ledger.to_sqlite(data, sqlite_path)

    conn = sqlite3.connect(sqlite_path)
    try:
        row = conn.execute(
            "SELECT serial_number, authority_key_identifier, ca_label, status, "
            "reason, expiry, revoked_at, not_before, metadata, common_name, sans "
            "FROM certificates"
        ).fetchone()
    finally:
        conn.close()

    (serial, aki, ca_label, status, reason, expiry, revoked_at, not_before, metadata, cn, sans) = row
    assert serial == "53494052835944942516701023896819511076934191012"
    assert aki == "6556ec45d3ce4d85a7151d6791ec5a313747425a"
    assert ca_label == ""
    assert status == "good"
    assert reason == 0
    assert expiry == "2026-12-07 23:30:00+00:00"
    assert revoked_at == "0001-01-01 00:00:00+00:00"
    assert not_before == "2026-09-07 17:30:00+00:00"
    assert metadata == "null"
    assert cn == "leaf.example"
    assert json.loads(sans) == ["leaf.example"]


def test_to_sqlite_revoked_cert_row(tmp_path: Path):
    data = {"certs": {}}
    ledger.record_issued(
        data, name="x", cn="x.example", sans=[], profile="server", serial="99",
        authority_key_id="AA:BB", not_before="2026-01-01T00:00:00Z",
        not_after="2027-01-01T00:00:00Z", pem="PEM",
    )
    ledger.mark_revoked(data, "x", reason="cessationofoperation")
    # mark_revoked stores revoked_at as a certinfo-shaped timestamp so
    # to_sqlite can run it through the same _cfssl_timestamp conversion
    # as any other date in the ledger.
    sqlite_path = tmp_path / "certstore.db"
    ledger.to_sqlite(data, sqlite_path)

    conn = sqlite3.connect(sqlite_path)
    try:
        status, reason, revoked_at = conn.execute(
            "SELECT status, reason, revoked_at FROM certificates"
        ).fetchone()
    finally:
        conn.close()

    assert status == "revoked"
    assert reason == ledger.REVOCATION_REASONS["cessationofoperation"]
    assert revoked_at != ledger._GO_ZERO_TIME
    assert revoked_at.endswith("+00:00")


def test_write_db_config(tmp_path: Path):
    db_config_path = tmp_path / "db.json"
    sqlite_path = tmp_path / "certstore.db"
    ledger.write_db_config(db_config_path, sqlite_path)
    config = json.loads(db_config_path.read_text())
    assert config == {"driver": "sqlite3", "data_source": str(sqlite_path)}
