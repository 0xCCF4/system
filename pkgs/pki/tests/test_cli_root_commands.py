"""Regression tests for cli.py's lazy `nix eval` behavior: it must only
run when the corresponding flag was omitted, and never during argument
parsing itself (see test_cli.py's ..._defaults tests for that half).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from pki import cli
from pki import repo
from pki import root as root_mod


@pytest.fixture(autouse=True)
def _fake_repo_root(monkeypatch, tmp_path):
    (tmp_path / "flake.nix").write_text("")
    repo.root.cache_clear()
    monkeypatch.chdir(tmp_path)
    yield
    repo.root.cache_clear()


def test_init_refuses_to_overwrite_existing_ca_cert(monkeypatch):
    def boom(**kwargs):
        raise AssertionError("cmd_init must bail out before ever touching root_mod.init")

    monkeypatch.setattr(root_mod, "init", boom)
    repo.ca_cert().parent.mkdir(parents=True, exist_ok=True)
    repo.ca_cert().write_text("EXISTING CERT")

    args = cli.build_parser().parse_args(["init"])
    assert cli.cmd_init(args) == 1
    assert repo.ca_cert().read_text() == "EXISTING CERT"  # untouched


def test_init_refuses_to_overwrite_existing_ca_key(monkeypatch):
    def boom(**kwargs):
        raise AssertionError("cmd_init must bail out before ever touching root_mod.init")

    monkeypatch.setattr(root_mod, "init", boom)
    repo.ca_key_ciphertext().parent.mkdir(parents=True, exist_ok=True)
    repo.ca_key_ciphertext().write_bytes(b"EXISTING CIPHERTEXT")

    args = cli.build_parser().parse_args(["init"])
    assert cli.cmd_init(args) == 1
    assert repo.ca_key_ciphertext().read_bytes() == b"EXISTING CIPHERTEXT"  # untouched


def test_init_force_overwrites_existing_ca(monkeypatch):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))
    monkeypatch.setattr(
        root_mod, "init", lambda **kwargs: root_mod.InitResult(ca_key_ciphertext=b"NEW-CT", ca_cert_pem="NEW-CERT")
    )
    repo.ca_cert().parent.mkdir(parents=True, exist_ok=True)
    repo.ca_cert().write_text("OLD CERT")

    args = cli.build_parser().parse_args(["init", "--force"])
    assert cli.cmd_init(args) == 0
    assert repo.ca_cert().read_text() == "NEW-CERT"


def test_init_skips_nix_eval_when_recipient_given(monkeypatch):
    def boom(**kwargs):
        raise AssertionError("nixeval.master_identity() must not be called when --recipient is given")

    monkeypatch.setattr(cli.nixeval, "master_identity", boom)
    monkeypatch.setattr(
        root_mod, "init", lambda **kwargs: root_mod.InitResult(ca_key_ciphertext=b"CT", ca_cert_pem="CERT")
    )

    args = cli.build_parser().parse_args(["init", "--recipient", "age1explicit..."])
    assert cli.cmd_init(args) == 0


def test_init_draws_recipient_via_nix_eval_when_omitted(monkeypatch):
    calls = []

    def fake_master_identity(**kwargs):
        calls.append(kwargs)
        return (Path("external/private/secrets/master.age"), "age1fromnixeval...")

    monkeypatch.setattr(cli.nixeval, "master_identity", fake_master_identity)

    captured = {}

    def fake_init(**kwargs):
        captured.update(kwargs)
        return root_mod.InitResult(ca_key_ciphertext=b"CT", ca_cert_pem="CERT")

    monkeypatch.setattr(root_mod, "init", fake_init)

    args = cli.build_parser().parse_args(["init"])
    assert cli.cmd_init(args) == 0
    assert len(calls) == 1
    assert captured["recipients"] == ["age1fromnixeval..."]


@pytest.fixture
def _fake_issue_deps(monkeypatch):
    monkeypatch.setattr(root_mod, "issue", lambda **kwargs: ("KEY-PEM", "CERT-PEM"))
    monkeypatch.setattr(
        cli.cfssl,
        "certinfo",
        lambda cert_pem: {
            "subject": {"common_name": "x.example"},
            "serial_number": "1",
            "authority_key_id": "AA:BB",
            "not_before": "2026-01-01T00:00:00Z",
            "not_after": "2027-01-01T00:00:00Z",
        },
    )


def test_issue_skips_nix_eval_when_identity_given(monkeypatch, _fake_issue_deps):
    def boom(**kwargs):
        raise AssertionError("nixeval.master_identity() must not be called when --identity is given")

    monkeypatch.setattr(cli.nixeval, "master_identity", boom)

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "my-identity.txt"])
    assert cli.cmd_issue(args) == 0


def test_issue_draws_identity_via_nix_eval_when_omitted(monkeypatch, _fake_issue_deps):
    calls = []

    def fake_master_identity(**kwargs):
        calls.append(kwargs)
        return (Path("external/private/secrets/master.age"), "age1fromnixeval...")

    monkeypatch.setattr(cli.nixeval, "master_identity", fake_master_identity)

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example"])
    assert cli.cmd_issue(args) == 0
    assert len(calls) == 1


def test_issue_records_ledger_entry(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    assert cli.cmd_issue(args) == 0

    data = cli.ledger_mod.load(repo.issued_certs_ledger())
    assert data["certs"]["x"]["cn"] == "x.example"
    assert data["certs"]["x"]["serial"] == "1"
    assert data["certs"]["x"]["revoked"] is False


def test_issue_writes_cert_to_private_not_public_pki_dir(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    assert cli.cmd_issue(args) == 0

    assert repo.issued_cert("x").read_text() == "CERT-PEM"
    assert not (repo.pki_dir() / "issued" / "x.pem").exists()


def test_issue_writes_key_beside_the_cert_not_repo_root(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    assert cli.cmd_issue(args) == 0

    key_path = repo.issued_cert("x").parent / "x-key.pem"
    assert key_path.read_text() == "KEY-PEM"
    assert not (repo.root() / "x-key.pem").exists()


def test_issue_defaults_to_ecdsa256(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    captured = {}
    monkeypatch.setattr(
        root_mod, "issue", lambda **kwargs: (captured.update(kwargs), ("KEY-PEM", "CERT-PEM"))[1]
    )

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    assert cli.cmd_issue(args) == 0
    assert captured["request"]["key"] == {"algo": "ecdsa", "size": 256}


def test_issue_rsa4096_overrides_key_algo(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    captured = {}
    monkeypatch.setattr(
        root_mod, "issue", lambda **kwargs: (captured.update(kwargs), ("KEY-PEM", "CERT-PEM"))[1]
    )

    args = cli.build_parser().parse_args(
        ["issue", "x", "--cn", "x.example", "--identity", "id.txt", "--rsa4096"]
    )
    assert cli.cmd_issue(args) == 0
    assert captured["request"]["key"] == {"algo": "rsa", "size": 4096}


def test_issue_flattens_comma_and_repeated_sans_into_the_request(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    captured = {}
    monkeypatch.setattr(
        root_mod, "issue", lambda **kwargs: (captured.update(kwargs), ("KEY-PEM", "CERT-PEM"))[1]
    )

    args = cli.build_parser().parse_args(
        [
            "issue", "x", "--cn", "x.example", "--identity", "id.txt",
            "--san", "a.example,b.example", "--san", "10.0.0.1",
        ]
    )
    assert cli.cmd_issue(args) == 0
    assert captured["request"]["hosts"] == ["a.example", "b.example", "10.0.0.1"]

    data = cli.ledger_mod.load(repo.issued_certs_ledger())
    assert data["certs"]["x"]["sans"] == ["a.example", "b.example", "10.0.0.1"]


def test_issue_ocsp_writes_agenix_secret_not_a_plaintext_file(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1thepubkey..."))
    captured_encrypt = {}
    monkeypatch.setattr(
        cli.age_mod,
        "encrypt",
        lambda *, recipients, plaintext: captured_encrypt.update(recipients=recipients, plaintext=plaintext)
        or b"AGE-CIPHERTEXT",
    )

    args = cli.build_parser().parse_args(["issue-ocsp", "--identity", "id.txt"])
    assert cli.cmd_issue_ocsp(args) == 0

    secret_path = repo.agenix_secret_path(host="lux", module="pki", ident="ocsp-responder-key")
    assert secret_path.read_bytes() == b"AGE-CIPHERTEXT"
    assert captured_encrypt["plaintext"] == "KEY-PEM"  # the raw key, never written to disk itself
    assert captured_encrypt["recipients"] == ["age1thepubkey..."]
    # No stray plaintext key file left anywhere in the repo root.
    assert not (repo.root() / "ocsp-responder-key.pem").exists()


def test_issue_ocsp_skips_nix_eval_for_recipient_when_given(monkeypatch, _fake_issue_deps):
    def boom(**kwargs):
        raise AssertionError("nixeval.master_identity() must not be called when --recipient is given")

    monkeypatch.setattr(cli.nixeval, "master_identity", boom)
    monkeypatch.setattr(cli.age_mod, "encrypt", lambda *, recipients, plaintext: b"CT")

    args = cli.build_parser().parse_args(
        ["issue-ocsp", "--identity", "id.txt", "--recipient", "age1explicit..."]
    )
    assert cli.cmd_issue_ocsp(args) == 0


def test_issue_expire_overrides_profile_expiry(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    config_path = repo.ca_config()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({
        "signing": {"default": {"expiry": "2190h"}, "profiles": {"server": {"expiry": "26280h"}}}
    }))

    captured = {}

    def fake_issue(**kwargs):
        # Must read the config's *content* here, while the tempdir
        # cli.py builds it in is still alive -- it's cleaned up by the
        # time cmd_issue returns.
        captured["config_content"] = json.loads(kwargs["config"].read_text())
        captured["config_path"] = kwargs["config"]
        return "KEY-PEM", "CERT-PEM"

    monkeypatch.setattr(root_mod, "issue", fake_issue)

    args = cli.build_parser().parse_args(
        ["issue", "x", "--cn", "x.example", "--identity", "id.txt", "--expire", "30d"]
    )
    assert cli.cmd_issue(args) == 0

    assert captured["config_content"]["signing"]["profiles"]["server"]["expiry"] == "720h"  # 30d
    assert captured["config_path"] != config_path  # a tempfile copy, not the real repo file
    # The real repo file itself must be untouched -- the override is a tempfile copy.
    assert json.loads(config_path.read_text())["signing"]["profiles"]["server"]["expiry"] == "26280h"


def test_issue_without_expire_uses_real_config_unmodified(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))

    captured = {}
    monkeypatch.setattr(
        root_mod, "issue", lambda **kwargs: (captured.update(kwargs), ("KEY-PEM", "CERT-PEM"))[1]
    )

    args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    assert cli.cmd_issue(args) == 0
    assert captured["config"] == repo.ca_config()


def test_issue_expire_unknown_profile_raises(monkeypatch, _fake_issue_deps):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))
    config_path = repo.ca_config()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps({"signing": {"profiles": {"server": {"expiry": "26280h"}}}}))

    args = cli.build_parser().parse_args(
        ["issue", "x", "--cn", "x.example", "--profile", "nonexistent", "--identity", "id.txt", "--expire", "30d"]
    )
    with pytest.raises(ValueError):
        cli.cmd_issue(args)


def test_gencrl_skips_nix_eval_when_identity_given(monkeypatch):
    def boom(**kwargs):
        raise AssertionError("nixeval.master_identity() must not be called when --identity is given")

    monkeypatch.setattr(cli.nixeval, "master_identity", boom)
    monkeypatch.setattr(root_mod, "gencrl", lambda **kwargs: "-----BEGIN X509 CRL-----\nFAKE\n-----END X509 CRL-----\n")

    args = cli.build_parser().parse_args(["gencrl", "--identity", "my-identity.txt"])
    assert cli.cmd_gencrl(args) == 0
    assert repo.crl().read_text().startswith("-----BEGIN X509 CRL-----")


def test_gencrl_draws_identity_via_nix_eval_when_omitted(monkeypatch):
    calls = []

    def fake_master_identity(**kwargs):
        calls.append(kwargs)
        return (Path("external/private/secrets/master.age"), "age1fromnixeval...")

    monkeypatch.setattr(cli.nixeval, "master_identity", fake_master_identity)
    monkeypatch.setattr(root_mod, "gencrl", lambda **kwargs: "-----BEGIN X509 CRL-----\nFAKE\n-----END X509 CRL-----\n")

    args = cli.build_parser().parse_args(["gencrl"])
    assert cli.cmd_gencrl(args) == 0
    assert len(calls) == 1


def test_revoke_needs_no_ca_key_at_all(monkeypatch, _fake_issue_deps):
    # Issue first so there's something to revoke.
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))
    issue_args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    cli.cmd_issue(issue_args)

    # No age/cfssl/nixeval mock needed for revoke itself -- it's a pure
    # ledger edit, and this test would fail loudly if cmd_revoke ever
    # started reaching for any of them.
    revoke_args = cli.build_parser().parse_args(["revoke", "x", "--reason", "keycompromise"])
    assert cli.cmd_revoke(revoke_args) == 0

    data = cli.ledger_mod.load(repo.issued_certs_ledger())
    assert data["certs"]["x"]["revoked"] is True
    assert data["certs"]["x"]["reason"] == "keycompromise"


def test_sync_db_needs_no_ca_key_or_nix_eval(monkeypatch, _fake_issue_deps, tmp_path):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))
    issue_args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    cli.cmd_issue(issue_args)

    def boom(**kwargs):
        raise AssertionError("sync-db must never touch nix eval or the CA key")

    # Re-arm after setup: the actual sync-db call under test must reach
    # none of these.
    monkeypatch.setattr(cli.nixeval, "master_identity", boom)
    monkeypatch.setattr(cli.root_mod, "issue", boom)
    monkeypatch.setattr(cli.root_mod, "gencrl", boom)

    db_path = tmp_path / "out" / "certstore.db"
    db_config_path = tmp_path / "out" / "db.json"
    sync_args = cli.build_parser().parse_args(
        ["sync-db", "--db", str(db_path), "--db-config", str(db_config_path)]
    )
    assert cli.cmd_sync_db(sync_args) == 0
    assert db_path.exists()
    assert db_config_path.exists()


def test_status_reports_from_the_ledger(monkeypatch, _fake_issue_deps, capsys):
    monkeypatch.setattr(cli.nixeval, "master_identity", lambda **kw: (Path("id"), "age1..."))
    issue_args = cli.build_parser().parse_args(["issue", "x", "--cn", "x.example", "--identity", "id.txt"])
    cli.cmd_issue(issue_args)

    assert cli.cmd_status() == 0
    out = capsys.readouterr().out
    assert "x.example" in out
    assert "server" in out
