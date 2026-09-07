"""Command-line entry point for the `pki` tool.

Subcommand groups, all run by the same person (the admin), always
off-host, always offline -- there is no automated or self-service
issuance path anywhere in this tool:
  init                    -- bootstrap the CA (once)
  issue-ocsp / issue      -- issue or renew a cert directly under the CA
  revoke                  -- mark a cert revoked in the ledger (no CA key)
  gencrl                  -- regenerate the CRL from the ledger
  status                  -- list issued certs + days-to-expiry

Every one of these is a local, explicitly-invoked CLI command -- never a
long-running server holding the CA key. Results get delivered to lux
purely through the normal Nix deploy path (commit the public cert +
updated ledger, import the private key via `agenix edit`, redeploy) --
this tool never talks to lux over the network at all.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from . import age as age_mod
from . import certinfo as certinfo_mod
from . import cfssl
from . import csr as csr_mod
from . import ledger as ledger_mod
from . import nixeval
from . import repo
from . import root as root_mod


_EXPIRY_UNITS_TO_HOURS = {"h": 1, "d": 24, "y": 24 * 365}


def parse_expiry(value: str) -> str:
    """Parses `--expire`'s value ("30d", "1y", "720h") into a cfssl-style
    Go duration string of hours ("720h") -- cfssl's own `expiry` config
    field is always hours, but typing e.g. "26280h" by hand is error-prone,
    so this is the one place that arithmetic happens. A year is 365 days,
    matching what pki/ca-config.json's own profiles already assume
    (26280h == 3 * 365 * 24).
    """
    error = argparse.ArgumentTypeError(
        f"invalid expiry {value!r} -- expected a positive number followed by h, d, or y (e.g. 30d, 1y, 720h)"
    )
    if len(value) < 2 or value[-1] not in _EXPIRY_UNITS_TO_HOURS:
        raise error
    try:
        amount = int(value[:-1])
    except ValueError:
        raise error from None
    if amount <= 0:
        raise error
    return f"{amount * _EXPIRY_UNITS_TO_HOURS[value[-1]]}h"


def parse_sans(raw: list[str]) -> list[str]:
    """Flattens `--san`'s repeated/comma-separated values ("--san a,b
    --san c" or any mix) into a single order-preserving, de-duplicated
    list, dropping empty entries (a stray trailing comma, etc.)."""
    seen: dict[str, None] = {}
    for item in raw:
        for name in item.split(","):
            name = name.strip()
            if name:
                seen[name] = None
    return list(seen)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pki")
    sub = parser.add_subparsers(dest="command", required=True)

    init_p = sub.add_parser("init", help="bootstrap the CA (offline, once)")
    init_p.add_argument("--cn", default="0xCCF4 CA")
    init_p.add_argument(
        "--recipient",
        action="append",
        default=None,
        dest="recipients",
        help="age or ssh public key to encrypt the CA key to -- repeatable. Defaults to "
        "nixos/secrets.nix's master identity pubkey (drawn live via `nix eval`) if omitted.",
    )
    init_p.add_argument(
        "--force",
        action="store_true",
        help="required if a CA already exists -- replacing it invalidates every cert issued under the old one",
    )

    issue_ocsp_p = sub.add_parser("issue-ocsp", help="issue/renew the OCSP responder cert (offline)")
    _add_signing_args(issue_ocsp_p)
    issue_ocsp_p.add_argument(
        "--recipient",
        action="append",
        default=None,
        dest="recipients",
        help="age or ssh public key to encrypt the new OCSP responder key's agenix secret to -- "
        "repeatable. Defaults to this repo's master identity pubkey (drawn live via `nix eval`), "
        "same as every other secret here, if omitted.",
    )

    issue_p = sub.add_parser("issue", help="issue/renew a leaf cert directly (offline)")
    issue_p.add_argument("name", help="a short local name for this cert, e.g. 'lux-matrix'")
    issue_p.add_argument("--cn", required=True)
    issue_p.add_argument(
        "--san", action="append", default=[], dest="sans", metavar="NAME[,NAME...]",
        help="a DNS name or IP this cert is also valid for -- repeatable (--san a --san b) and/or "
        "comma-separated (--san a,b) in a single flag; the CN itself is always included too",
    )
    issue_p.add_argument("--profile", default="server")
    issue_p.add_argument(
        "--expire", type=parse_expiry, default=None, metavar="<N>h|<N>d|<N>y",
        help="override the profile's default validity, e.g. 30d, 12h, 1y",
    )
    issue_p.add_argument(
        "--rsa4096", action="store_true",
        help="use RSA-4096 instead of the default ECDSA-256 key (e.g. for a device that doesn't "
        "support ECDSA certs)",
    )
    _add_signing_args(issue_p)

    revoke_p = sub.add_parser("revoke", help="mark a cert revoked in the ledger (no CA key needed)")
    revoke_p.add_argument("name")
    revoke_p.add_argument("--reason", default="unspecified", choices=sorted(ledger_mod.REVOCATION_REASONS))

    gencrl_p = sub.add_parser("gencrl", help="regenerate the CRL from the ledger (offline)")
    gencrl_p.add_argument("--identity", type=Path, default=None, help=_IDENTITY_HELP)
    gencrl_p.add_argument("--ca", type=Path, default=None, help="defaults to the repo's own pki/root-ca.pem")
    gencrl_p.add_argument(
        "--ca-key", type=Path, default=None,
        help="the age-encrypted CA key -- defaults to external/private/secrets/pki/root-ca-key.age",
    )

    sub.add_parser("status", help="list issued certs + days-to-expiry from the ledger")

    sync_db_p = sub.add_parser(
        "sync-db", help="convert the ledger to a sqlite cfssl db (no CA key needed)"
    )
    sync_db_p.add_argument(
        "--ledger", type=Path, default=None, help="defaults to the repo's own pki/issued-certs.json"
    )
    sync_db_p.add_argument("--db", type=Path, required=True, help="sqlite output path")
    sync_db_p.add_argument("--db-config", type=Path, required=True, help="db.json output path")

    return parser


_IDENTITY_HELP = (
    "private key file (age or ssh format) to decrypt --ca-key with. Defaults to "
    "nixos/secrets.nix's master identity path (drawn live via `nix eval`) if omitted -- "
    "pass this explicitly if the CA key is encrypted to a different identity."
)


def _add_signing_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--identity", type=Path, default=None, help=_IDENTITY_HELP)
    parser.add_argument("--ca", type=Path, default=None, help="defaults to the repo's own pki/root-ca.pem")
    parser.add_argument(
        "--ca-key", type=Path, default=None,
        help="the age-encrypted CA key -- defaults to external/private/secrets/pki/root-ca-key.age",
    )
    parser.add_argument(
        "--config", type=Path, default=None, help="defaults to the repo's own pki/ca-config.json"
    )


def _resolve_identity(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    identity, _pubkey = nixeval.master_identity()
    return identity


def cmd_init(args: argparse.Namespace) -> int:
    """Writes the CA cert straight to pki/root-ca.pem and the
    age-encrypted key straight to external/private/secrets/pki/
    root-ca-key.age -- both real repo locations, resolved from wherever
    this checkout actually is (see repo.py).
    """
    ca_cert = repo.ca_cert()
    ca_key_ciphertext = repo.ca_key_ciphertext()
    existing = [p for p in (ca_cert, ca_key_ciphertext) if p.exists()]
    if existing and not args.force:
        existing_list = ", ".join(str(p) for p in existing)
        print(f"error: CA already exists ({existing_list}) -- pass --force to replace it", file=sys.stderr)
        return 1

    recipients = args.recipients
    if recipients is None:
        _identity, pubkey = nixeval.master_identity()
        recipients = [pubkey]

    request = csr_mod.build_csr_request(cn=args.cn)
    result = root_mod.init(ca_request=request, recipients=recipients)

    ca_key_ciphertext.parent.mkdir(parents=True, exist_ok=True)
    ca_key_ciphertext.write_bytes(result.ca_key_ciphertext)

    ca_cert.parent.mkdir(parents=True, exist_ok=True)
    ca_cert.write_text(result.ca_cert_pem)

    print(f"wrote {ca_key_ciphertext} (age-encrypted) and {ca_cert}")
    return 0


def _config_with_expiry_override(config_path: Path, *, profile: str, expiry: str, tmp_dir: Path) -> Path:
    """`expiry` is already a cfssl-style Go duration string (e.g. "720h"),
    produced by `parse_expiry` at argument-parsing time."""
    config = json.loads(config_path.read_text())
    try:
        config["signing"]["profiles"][profile]["expiry"] = expiry
    except KeyError:
        raise ValueError(f"profile {profile!r} not found in {config_path}") from None
    override_path = tmp_dir / "ca-config-override.json"
    override_path.write_text(json.dumps(config))
    return override_path


def _issue_and_record(
    *, name: str, request: dict, profile: str, args: argparse.Namespace
) -> tuple[str, str]:
    ca = args.ca or repo.ca_cert()
    ca_key_ciphertext = args.ca_key or repo.ca_key_ciphertext()
    config = args.config or repo.ca_config()
    identity = _resolve_identity(args.identity)
    expire = getattr(args, "expire", None)

    with tempfile.TemporaryDirectory() as tmp:
        if expire is not None:
            config = _config_with_expiry_override(config, profile=profile, expiry=expire, tmp_dir=Path(tmp))

        db_path = Path(tmp) / "certstore.db"
        db_config_path = Path(tmp) / "db.json"
        ledger_mod.to_sqlite({"certs": {}}, db_path)
        ledger_mod.write_db_config(db_config_path, db_path)

        key_pem, cert_pem = root_mod.issue(
            request=request,
            profile=profile,
            ca=ca,
            ca_key_ciphertext=ca_key_ciphertext,
            identity=identity,
            config=config,
            db_config=db_config_path,
        )

    info = cfssl.certinfo(cert_pem)
    data = ledger_mod.load(repo.issued_certs_ledger())
    ledger_mod.record_issued(
        data,
        name=name,
        cn=info["subject"]["common_name"],
        sans=request.get("hosts", []),
        profile=profile,
        serial=info["serial_number"],
        authority_key_id=info["authority_key_id"],
        not_before=info["not_before"],
        not_after=info["not_after"],
        pem=cert_pem,
    )
    ledger_mod.save(repo.issued_certs_ledger(), data)

    return key_pem, cert_pem


def cmd_issue_ocsp(args: argparse.Namespace) -> int:
    """Writes the agenix secret directly (age-encrypted to
    --recipient/the master identity, at the exact path
    `noxa.secrets.def` expects -- see repo.agenix_secret_path) instead of
    a plaintext file + a manual `agenix edit` paste step. The plaintext
    key never touches disk at all: it goes straight from `_issue_and_record`
    (in memory) to `age_mod.encrypt`.

    Still needs `agenix rekey` run afterward -- this writes the same
    master-encrypted raw secret `agenix edit` would have produced, not
    the final per-host-recipient copy NixOS actually decrypts at boot.
    """
    recipients = args.recipients
    if recipients is None:
        _identity, pubkey = nixeval.master_identity()
        recipients = [pubkey]

    request = csr_mod.build_csr_request(cn="OCSP Responder")
    key_pem, cert_pem = _issue_and_record(name="ocsp-responder", request=request, profile="ocsp", args=args)

    ocsp_cert = repo.ocsp_responder_cert()
    ocsp_cert.parent.mkdir(parents=True, exist_ok=True)
    ocsp_cert.write_text(cert_pem)

    secret_path = repo.agenix_secret_path(host="lux", module="pki", ident="ocsp-responder-key")
    secret_path.parent.mkdir(parents=True, exist_ok=True)
    secret_path.write_bytes(age_mod.encrypt(recipients=recipients, plaintext=key_pem))

    print(f"wrote {ocsp_cert} and {secret_path} (age-encrypted)")
    print(f"run `agenix rekey` to make {secret_path.name} usable on lux, then deploy.")
    return 0


def cmd_issue(args: argparse.Namespace) -> int:
    key_kwargs = {"key_algo": "rsa", "key_size": 4096} if args.rsa4096 else {}
    request = csr_mod.build_csr_request(cn=args.cn, sans=parse_sans(args.sans), **key_kwargs)
    key_pem, cert_pem = _issue_and_record(name=args.name, request=request, profile=args.profile, args=args)

    cert_path = repo.issued_cert(args.name)
    cert_path.parent.mkdir(parents=True, exist_ok=True)
    cert_path.write_text(cert_pem)

    # Beside the cert, in the same private directory -- not the repo
    # root, which is the public, git-tracked tree the plaintext key must
    # never end up committed to.
    key_path = cert_path.parent / f"{args.name}-key.pem"
    key_path.write_text(key_pem)

    print(f"wrote {cert_path} and {key_path}")
    print(f"{key_path} is plaintext -- import it via `agenix edit`, then delete it here. Never commit it.")
    return 0


def cmd_revoke(args: argparse.Namespace) -> int:
    data = ledger_mod.load(repo.issued_certs_ledger())
    ledger_mod.mark_revoked(data, args.name, reason=args.reason)
    ledger_mod.save(repo.issued_certs_ledger(), data)
    print(f"marked {args.name!r} revoked ({args.reason}) in {repo.issued_certs_ledger()}")
    print("takes effect for OCSP clients once this is committed and deployed (lux's own "
          "ocsprefresh timer re-signs against whatever was last deployed)")
    return 0


def cmd_gencrl(args: argparse.Namespace) -> int:
    ca = args.ca or repo.ca_cert()
    ca_key_ciphertext = args.ca_key or repo.ca_key_ciphertext()
    identity = _resolve_identity(args.identity)

    data = ledger_mod.load(repo.issued_certs_ledger())
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "certstore.db"
        db_config_path = Path(tmp) / "db.json"
        ledger_mod.to_sqlite(data, db_path)
        ledger_mod.write_db_config(db_config_path, db_path)

        crl_pem = root_mod.gencrl(
            ca=ca, ca_key_ciphertext=ca_key_ciphertext, identity=identity, db_config=db_config_path
        )

    crl_path = repo.crl()
    crl_path.parent.mkdir(parents=True, exist_ok=True)
    crl_path.write_text(crl_pem)
    print(f"wrote {crl_path}")
    return 0


def cmd_status() -> int:
    data = ledger_mod.load(repo.issued_certs_ledger())
    certs = data.get("certs", {})
    if not certs:
        print("no certs in the ledger")
        return 0
    for name, entry in sorted(certs.items()):
        days = certinfo_mod.days_until_expiry({"not_after": entry["not_after"]})
        state = f"REVOKED ({entry['reason']})" if entry["revoked"] else f"expires in {days}d"
        print(f"{name}: {entry['cn']} [{entry['profile']}] -- {state}")
    return 0


def cmd_sync_db(args: argparse.Namespace) -> int:
    """Regenerates a cfssl-schema sqlite DB from the ledger -- no CA key
    involved, purely a data conversion. This is what `hosts/lux/pki.nix`
    invokes at Nix build time so lux's `cfssl-ocspserve`/`ocsprefresh`
    always read a fresh DB derived from whatever's committed, without any
    sqlite file ever needing to be committed itself.
    """
    ledger_path = args.ledger or repo.issued_certs_ledger()
    data = ledger_mod.load(ledger_path)
    ledger_mod.to_sqlite(data, args.db)
    ledger_mod.write_db_config(args.db_config, args.db)
    print(f"wrote {args.db} and {args.db_config} from {ledger_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "init":
            return cmd_init(args)
        if args.command == "issue-ocsp":
            return cmd_issue_ocsp(args)
        if args.command == "issue":
            return cmd_issue(args)
        if args.command == "revoke":
            return cmd_revoke(args)
        if args.command == "gencrl":
            return cmd_gencrl(args)
        if args.command == "status":
            return cmd_status()
        if args.command == "sync-db":
            return cmd_sync_db(args)
    except repo.RepoRootNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        # Without this, a bare "returned non-zero exit status 1" is all
        # that surfaces -- capture_output=True means the actual reason
        # (a missing file, a profile that doesn't exist, ...) is sitting
        # right there in .stderr and just never gets printed otherwise.
        print(f"error: {' '.join(str(a) for a in exc.cmd)} failed:", file=sys.stderr)
        if exc.stderr:
            stderr_text = exc.stderr if isinstance(exc.stderr, str) else exc.stderr.decode(errors="replace")
            print(stderr_text.strip(), file=sys.stderr)
        return 1

    parser.error(f"unknown command {args.command!r}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
