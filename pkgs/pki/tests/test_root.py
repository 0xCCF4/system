"""Regression tests for root.py's handling of the CA key.

These monkeypatch age.py/cfssl.py (unit-shaped: no real age/cfssl binary
involved) specifically to pin down the security property this module
exists for: the CA key's plaintext is never written to disk, not even
transiently -- init() only ever returns ciphertext, and issue()/gencrl()
hand cfssl the plaintext only via an environment variable
(`-ca-key env:...`), never a file.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from pki import root as root_mod


@pytest.fixture(autouse=True)
def _fake_age(monkeypatch):
    monkeypatch.setattr(
        root_mod.age_mod, "encrypt", lambda *, recipients, plaintext: f"AGE-CIPHERTEXT[{plaintext}]".encode()
    )
    monkeypatch.setattr(
        root_mod.age_mod, "decrypt", lambda *, identity, ciphertext_path: "DECRYPTED-CA-KEY-PEM"
    )


def test_init_never_returns_plaintext_ca_key(monkeypatch):
    monkeypatch.setattr(root_mod.cfssl, "initca", lambda request: ("KEY-PEM", "CSR-PEM", "CERT-PEM"))

    result = root_mod.init(ca_request={"CN": "0xCCF4 CA"}, recipients=["age1exampleexampleexample"])

    assert not hasattr(result, "ca_key_pem")
    assert result.ca_key_ciphertext == b"AGE-CIPHERTEXT[KEY-PEM]"
    assert result.ca_cert_pem == "CERT-PEM"


def test_issue_never_passes_ca_key_as_a_file(monkeypatch, tmp_path: Path):
    captured = {}

    def fake_gencert(**kwargs):
        captured.update(kwargs)
        return ("LEAF-KEY-PEM", "LEAF-CERT-PEM")

    monkeypatch.setattr(root_mod.cfssl, "gencert", fake_gencert)

    key_pem, cert_pem = root_mod.issue(
        request={"CN": "leaf.example"},
        profile="server",
        ca=tmp_path / "ca.pem",
        ca_key_ciphertext=tmp_path / "ca-key.pem.age",
        identity=tmp_path / "identity",
        config=tmp_path / "ca-config.json",
        db_config=tmp_path / "db.json",
    )

    assert (key_pem, cert_pem) == ("LEAF-KEY-PEM", "LEAF-CERT-PEM")
    assert isinstance(captured["ca_key"], str) and captured["ca_key"].startswith("env:")
    env_var_name = captured["ca_key"].removeprefix("env:")
    assert captured["extra_env"][env_var_name] == "DECRYPTED-CA-KEY-PEM"
    assert captured["profile"] == "server"


def test_gencrl_never_passes_ca_key_as_a_file(monkeypatch, tmp_path: Path):
    captured = {}

    def fake_gencrl(**kwargs):
        captured.update(kwargs)
        return "-----BEGIN X509 CRL-----\nFAKE\n-----END X509 CRL-----\n"

    monkeypatch.setattr(root_mod.cfssl, "gencrl", fake_gencrl)

    crl_pem = root_mod.gencrl(
        ca=tmp_path / "ca.pem",
        ca_key_ciphertext=tmp_path / "ca-key.pem.age",
        identity=tmp_path / "identity",
        db_config=tmp_path / "db.json",
    )

    assert crl_pem.startswith("-----BEGIN X509 CRL-----")
    assert isinstance(captured["ca_key"], str) and captured["ca_key"].startswith("env:")
    env_var_name = captured["ca_key"].removeprefix("env:")
    assert captured["extra_env"][env_var_name] == "DECRYPTED-CA-KEY-PEM"
