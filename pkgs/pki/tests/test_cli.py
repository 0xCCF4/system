import pytest

from pki.cli import build_parser, parse_expiry, parse_sans


def test_parse_expiry_hours():
    assert parse_expiry("12h") == "12h"


def test_parse_expiry_days():
    assert parse_expiry("30d") == "720h"


def test_parse_expiry_years():
    assert parse_expiry("1y") == "8760h"
    assert parse_expiry("3y") == "26280h"  # matches pki/ca-config.json's server profile


@pytest.mark.parametrize("bad", ["30", "d30", "0d", "-5d", "5x", "", "h"])
def test_parse_expiry_rejects_invalid(bad):
    with pytest.raises(Exception):
        parse_expiry(bad)


def test_parses_init_defaults():
    args = build_parser().parse_args(["init"])
    assert args.command == "init"
    assert args.cn == "0xCCF4 CA"
    assert args.recipients is None
    assert args.force is False


def test_parses_init_with_force():
    args = build_parser().parse_args(["init", "--force"])
    assert args.force is True


def test_parses_init_with_explicit_cn_and_recipients():
    args = build_parser().parse_args(
        ["init", "--cn", "Example CA", "--recipient", "age1abc...", "--recipient", "ssh-ed25519 AAAA..."]
    )
    assert args.cn == "Example CA"
    assert args.recipients == ["age1abc...", "ssh-ed25519 AAAA..."]


def test_parses_issue_with_sans():
    args = build_parser().parse_args(
        ["issue", "lux-matrix", "--cn", "matrix.example.internal", "--san", "matrix.example.internal", "--san", "10.0.0.1"]
    )
    assert args.command == "issue"
    assert args.name == "lux-matrix"
    assert args.cn == "matrix.example.internal"
    assert args.sans == ["matrix.example.internal", "10.0.0.1"]
    assert args.profile == "server"


def test_parse_sans_repeated_flags():
    assert parse_sans(["a.example", "b.example"]) == ["a.example", "b.example"]


def test_parse_sans_comma_separated():
    assert parse_sans(["a.example,b.example,10.0.0.1"]) == ["a.example", "b.example", "10.0.0.1"]


def test_parse_sans_mixed_repeat_and_comma():
    assert parse_sans(["a.example,b.example", "c.example"]) == ["a.example", "b.example", "c.example"]


def test_parse_sans_dedupes_preserving_order():
    assert parse_sans(["a.example", "b.example", "a.example"]) == ["a.example", "b.example"]


def test_parse_sans_drops_empty_entries():
    assert parse_sans(["a.example,,b.example", " ", ""]) == ["a.example", "b.example"]


def test_parse_sans_empty_input():
    assert parse_sans([]) == []


def test_parses_issue_repo_relative_defaults():
    args = build_parser().parse_args(["issue", "x", "--cn", "x.example"])
    assert args.identity is None
    assert args.ca is None
    assert args.ca_key is None
    assert args.config is None
    assert args.expire is None
    assert args.rsa4096 is False


def test_parses_issue_with_rsa4096():
    args = build_parser().parse_args(["issue", "x", "--cn", "x.example", "--rsa4096"])
    assert args.rsa4096 is True


def test_parses_issue_with_expire_days():
    args = build_parser().parse_args(["issue", "x", "--cn", "x.example", "--expire", "30d"])
    assert args.expire == "720h"


def test_parses_issue_with_expire_years():
    args = build_parser().parse_args(["issue", "x", "--cn", "x.example", "--expire", "1y"])
    assert args.expire == "8760h"


def test_parses_issue_with_expire_hours():
    args = build_parser().parse_args(["issue", "x", "--cn", "x.example", "--expire", "12h"])
    assert args.expire == "12h"


def test_parses_issue_with_invalid_expire_rejected():
    with pytest.raises(SystemExit):
        build_parser().parse_args(["issue", "x", "--cn", "x.example", "--expire", "30"])  # no unit suffix


def test_parses_issue_ocsp():
    args = build_parser().parse_args(["issue-ocsp"])
    assert args.command == "issue-ocsp"
    assert args.identity is None
    assert args.ca is None
    assert args.recipients is None


def test_parses_issue_ocsp_with_recipients():
    args = build_parser().parse_args(
        ["issue-ocsp", "--recipient", "age1abc...", "--recipient", "ssh-ed25519 AAAA..."]
    )
    assert args.recipients == ["age1abc...", "ssh-ed25519 AAAA..."]


def test_parses_revoke():
    args = build_parser().parse_args(["revoke", "lux-matrix", "--reason", "keycompromise"])
    assert args.command == "revoke"
    assert args.name == "lux-matrix"
    assert args.reason == "keycompromise"


def test_parses_revoke_default_reason():
    args = build_parser().parse_args(["revoke", "x"])
    assert args.reason == "unspecified"


def test_parses_gencrl():
    args = build_parser().parse_args(["gencrl"])
    assert args.command == "gencrl"
    assert args.identity is None
    assert args.ca is None
    assert args.ca_key is None


def test_parses_status():
    args = build_parser().parse_args(["status"])
    assert args.command == "status"


def test_parses_sync_db():
    args = build_parser().parse_args(["sync-db", "--db", "out.db", "--db-config", "out.json"])
    assert args.command == "sync-db"
    assert args.ledger is None
    assert str(args.db) == "out.db"
    assert str(args.db_config) == "out.json"
