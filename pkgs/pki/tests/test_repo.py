from pathlib import Path

import pytest

from pki import repo


@pytest.fixture(autouse=True)
def _clear_root_cache():
    # root() is lru_cache'd (real usage: found once per process, that's
    # the whole point) -- tests change cwd repeatedly, so the cache must
    # not leak between them.
    repo.root.cache_clear()
    yield
    repo.root.cache_clear()


def test_find_repo_root_at_cwd_itself(tmp_path: Path):
    (tmp_path / "flake.nix").write_text("")
    assert repo.find_repo_root(tmp_path) == tmp_path


def test_find_repo_root_searches_upward_from_a_subdir(tmp_path: Path):
    (tmp_path / "flake.nix").write_text("")
    subdir = tmp_path / "pki" / "deeper"
    subdir.mkdir(parents=True)
    assert repo.find_repo_root(subdir) == tmp_path


def test_find_repo_root_raises_when_none_found(tmp_path: Path):
    lonely = tmp_path / "nowhere"
    lonely.mkdir()
    with pytest.raises(repo.RepoRootNotFoundError):
        repo.find_repo_root(lonely)


def test_root_resolves_from_cwd_via_monkeypatch(tmp_path: Path, monkeypatch):
    (tmp_path / "flake.nix").write_text("")
    monkeypatch.chdir(tmp_path)
    assert repo.root() == tmp_path.resolve()


def test_root_resolves_when_invoked_from_a_subdirectory(tmp_path: Path, monkeypatch):
    # Regression test: running `pki` from inside pki/ (instead of the
    # repo root) previously wrote everything one directory too deep with
    # no error until a later step failed on a missing file.
    (tmp_path / "flake.nix").write_text("")
    subdir = tmp_path / "pki"
    subdir.mkdir()
    monkeypatch.chdir(subdir)
    assert repo.root() == tmp_path.resolve()


def test_derived_paths_are_all_under_the_resolved_root(tmp_path: Path, monkeypatch):
    (tmp_path / "flake.nix").write_text("")
    monkeypatch.chdir(tmp_path)

    resolved = tmp_path.resolve()
    assert repo.ca_cert() == resolved / "pki" / "root-ca.pem"
    assert repo.ocsp_responder_cert() == resolved / "pki" / "ocsp-responder-cert.pem"
    assert repo.ca_config() == resolved / "pki" / "ca-config.json"
    assert repo.crl() == resolved / "pki" / "crl.pem"
    assert repo.ca_key_ciphertext() == (
        resolved / "external" / "private" / "secrets" / "pki" / "root-ca-key.age"
    )
    assert repo.issued_certs_ledger() == (
        resolved / "external" / "private" / "secrets" / "pki" / "issued-certs.json"
    )
    assert repo.issued_cert("lux-matrix") == (
        resolved / "external" / "private" / "secrets" / "pki" / "issued" / "lux-matrix.pem"
    )
    assert repo.agenix_secret_path(host="lux", module="pki", ident="ocsp-responder-key") == (
        resolved / "external" / "private" / "secrets" / "host" / "lux" / "pki" / "ocsp-responder-key.age"
    )
