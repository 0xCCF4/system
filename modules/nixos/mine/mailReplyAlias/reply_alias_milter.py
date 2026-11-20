#!/usr/bin/env python3
"""reply-alias-milter

A Postfix milter that rewrites the envelope sender and From: header of an
outbound (authenticated submission) *reply* to the alias the original message
was delivered to.

How it works
------------
The milter sees every message that Postfix accepts.  Two different jobs run
on that one stream:

* Inbound mail (no SASL login) is only *recorded*.  For each envelope
  recipient and each Message-ID of the message, one row goes into a small
  SQLite store (`message-id -> recipient address`).  The recipient is the
  alias the mail was addressed to, for example `github@yourdomain`.

* Outbound mail (SASL login) is the reply path.  The reply carries the
  original message's Message-ID in its In-Reply-To: and References: headers.
  The store yields the alias that message was delivered to.  If the
  authenticated account may send from that alias (checked against Postfix's
  own `vaccounts` sender-login map) and the From: header is the account's
  primary address, the milter rewrites the envelope sender and the From:
  header to the alias.

The store replaces an earlier design that searched the delivered copy in the
user's Maildir for its X-Original-To: header.  That design could not work:
Dovecot writes mail files 0600 in a 0700 directory owned by the storage user,
so no other account can read them.  Reading them would also have meant
trusting a header that the mailbox owner can inject by mailing themselves.

Safeguards
----------
* Only rewrites SASL-authenticated submission, never inbound port-25 mail.
* Only rewrites to addresses the Postfix `sender_login_maps` map authorises
  for the authenticated account (queried via `postmap`).
* Only rewrites when the reply is sent from the account's primary address.
  An explicitly chosen From: identity is left alone.
* Skips signing/encryption wrappers (PGP/S/MIME, DKIM), so a signature is
  never broken by rewriting From or the envelope.
* Every value that crosses a boundary (subprocess argument, SQL parameter,
  header value, log line) is validated or cleaned first.
* Fail-open: every error path, including an unexpected exception, leaves the
  message untouched.  Postfix's milter_default_action would otherwise defer
  or refuse the mail.
"""

import logging
import os
import re
import sqlite3
import subprocess
import sys
import threading
import time

from email.utils import parseaddr

import Milter

# The milter hook API.  Note the import style: `Milter` must stay the module.
# Assigning `Milter.factory` on the `Milter.Milter` class instead of on the
# package module leaves the default no-op class in place, and then every
# message passes through untouched without any error.
Base = Milter.Base
CONTINUE = Milter.CONTINUE
runmilter = Milter.runmilter

# Debug logging goes to stderr, which systemd routes to the journal.  Watch it
# with `journalctl -u reply-alias-milter -f`.  Set debug = true in the NixOS
# option and restart the service for more detail.
log = logging.getLogger("reply-alias")
_RUNNING = {}


def setup_logging(debug):
    """Configure stderr logging once; debug toggles level and detail."""
    if _RUNNING:
        return
    _RUNNING["yes"] = True
    level = logging.DEBUG if debug else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(name)s %(levelname)s: %(message)s"))
    log.addHandler(handler)
    log.setLevel(level)
    log.propagate = False


_LOG_MAX = 300


def _emit(status, detail=""):
    """Write one status line for a message to stderr and flush it immediately.

    Every line starts with the milter name so the two milters are easy to
    separate in the journal.  One line per mail, never per event.  The detail
    is attacker-influenced, so it is stripped of control characters and cut
    to a fixed length.
    """
    line = "reply-alias: %s" % _log_safe(status, 80)
    if detail:
        line += ": %s" % _log_safe(detail, _LOG_MAX)
    sys.stderr.write(line + "\n")
    sys.stderr.flush()


# ---------------------------------------------------------------------------
# Sanitizers
# ---------------------------------------------------------------------------
# Every value that reaches a boundary (a subprocess argument, an SQL
# parameter, a path, or an address written back into mail) is validated
# against its real grammar before it is used.  A value that fails is dropped
# (fail open): the message is left untouched rather than rewritten badly.

# A safe Message-ID consists of dot-atom characters only.  It may never
# contain whitespace, control characters, or angle brackets.
_SAFE_DOT_ATOM = set(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!"
    "#$%&'*+-/=?^_`{|}~."
)

# A real Message-ID is at least a few characters long.  Any shorter token
# found in an In-Reply-To / References header is almost certainly not a
# conforming ID.
_MIN_MSGID_LEN = 8

_CTL_RE = re.compile(r"[\x00-\x1f\x7f]+")


def _log_safe(text, limit):
    """Strip control characters from a value bound for the journal, and cut
    it to `limit` characters.  A hostile header can otherwise inject fake
    lines into the journal or flood it."""
    if not text:
        return ""
    clean = "".join(c for c in text if c == "\t" or (ord(c) >= 0x20 and ord(c) != 0x7F))
    return clean[:limit]


def _clean_header_value(value):
    """Return `value` with control characters replaced by spaces.

    A header value from libmilter can carry CR, LF and other control
    characters, and this value may be written back into a header.  Anything
    below 0x20 or 0x7f is therefore removed.
    """
    if not value:
        return ""
    return _CTL_RE.sub(" ", value).strip()


def is_safe_msgid(mid):
    """True if `mid` looks like a real Message-ID (id-left@id-right, dot-atom).

    The reply's In-Reply-To / References headers are attacker-controlled, so
    this gate rejects junk before it becomes a SQL parameter or a stored key.
    A Message-ID's two halves (id-left, id-right) are each dot-atom,
    separated by @.  The @ itself is not a dot-atom character.
    """
    if not mid or len(mid) < _MIN_MSGID_LEN or len(mid) > 998:
        return False
    left, sep, right = mid.partition("@")
    if not sep or not left or not right or "@" in right:
        return False
    return all(c in _SAFE_DOT_ATOM for c in left) and all(c in _SAFE_DOT_ATOM for c in right)


# A rewritten address must be a real, well-formed email address: a dot-atom
# local part and a hostname/domain part with no whitespace, control
# characters, angle brackets, or quotes.  This value is written back into the
# envelope and the From header, so header injection is prevented here.
_EMAIL_RE = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
)


def safe_address(value):
    """Return `value` as a bare validated email address, or None if invalid.

    Accepts an optional surrounding `<...>` (as written by Postfix delivery).
    Rejects any value containing whitespace, control characters, or other
    header-breaking characters.
    """
    if not value:
        return None
    v = value.strip()
    if v.startswith("<") and v.endswith(">"):
        v = v[1:-1]
    if any(c.isspace() or ord(c) < 0x20 or ord(c) == 0x7F for c in v):
        return None
    if len(v) > 320 or not _EMAIL_RE.match(v):
        return None
    return v


def safe_display_name(name):
    """Return `name` with any character that could break a header removed.

    `name` comes from the reply's From header, so it is attacker-controlled
    and may not carry CR/LF or other control characters into the rewritten
    header.
    """
    return _clean_header_value(name)


# Characters that force a display name to be a quoted string (RFC 5322
# specials).  A name without them can stay unquoted.
_SPECIALS = set('()<>[]:;@\\,."')


def format_address(name, addr):
    """Build a From header value from an optional display name and an address."""
    name = safe_display_name(name)
    if not name:
        return addr
    # An RFC 2047 encoded word is already a valid phrase.
    if "=?" not in name and any(c in _SPECIALS for c in name):
        name = '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return "%s <%s>" % (name, addr)


# ---------------------------------------------------------------------------
# Message-ID extraction
# ---------------------------------------------------------------------------

# A token is anything inside <...>, which is how Message-IDs appear in
# In-Reply-To / References.  Leading and trailing dots (dot-unstuffing) are
# stripped.
_MID_RE = re.compile(r"<([^<>]*)>")

# Upper bounds.  A hostile message can carry an unlimited number of headers,
# Message-IDs and recipients, and every one of them would cost memory, store
# rows or SQL parameters.
_MAX_HEADERS = 2000
_MAX_MESSAGE_IDS = 10
_MAX_RCPTS = 20


def extract_message_ids(value):
    """Return a list of normalized message-id strings from a header value."""
    if not value:
        return []
    ids = []
    for tok in _MID_RE.findall(value):
        tok = tok.strip().rstrip(".").lstrip(".")
        if tok:
            ids.append(tok)
    return ids


# ---------------------------------------------------------------------------
# Configuration (read from the NixOS-generated config file)
# ---------------------------------------------------------------------------

# The NixOS module renders the config as an immutable store file and points
# REPLY_ALIAS_CONFIG at it.  Keep /etc/reply-alias.conf as a fallback for
# manual setups; a missing file degrades to a no-op.
CONFIG_PATH = os.environ.get("REPLY_ALIAS_CONFIG", "/etc/reply-alias.conf")


def load_config(path=CONFIG_PATH):
    cfg = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                cfg[key.strip()] = value.strip()
    except OSError as exc:
        # Missing/unreadable config: keep running as a harmless no-op, but say
        # so once at startup.  A silent no-op looks exactly like a healthy
        # milter, and then replies are not rewritten with no trace anywhere.
        _emit("error", "cannot read config %s: %s; rewriting is off" % (path, exc))
    return cfg


CONFIG = load_config()

SOCKET = CONFIG.get("socket", "/run/reply-alias/reply-alias.sock")
STATEFILE = CONFIG.get("statefile", "/var/lib/reply-alias/aliases.sqlite3")
VACCOUNTS_MAP = CONFIG.get("vaccountsmap")
POSTMAP = CONFIG.get("postmap", "/run/current-system/sw/bin/postmap")
DEBUG = CONFIG.get("debug", "0") in ("1", "true", "yes", "on")
try:
    RETENTION_DAYS = max(1, int(CONFIG.get("retentiondays", "90")))
except ValueError:
    RETENTION_DAYS = 90

# Accounts that opt in to reply-alias rewriting, keyed by lowercased SASL
# login:  login -> primary address.  Which aliases an account may reply as is
# resolved at runtime from Postfix's vaccounts sender-login map.
ACCOUNTS = {}
for key, value in CONFIG.items():
    if key.startswith("account."):
        login = key.split(".", 1)[1].strip().lower()
        primary = safe_address(value)
        if login and primary:
            ACCOUNTS[login] = primary

# Lowercased primary addresses; mail delivered straight to one of these is
# never rewritten to it.
PRIMARIES = {primary.lower() for primary in ACCOUNTS.values()}

setup_logging(DEBUG)

log.debug("reply-alias milter starting (debug on)")
log.debug("socket=%s state=%s vaccounts=%s", SOCKET, STATEFILE, VACCOUNTS_MAP)


# ---------------------------------------------------------------------------
# The alias store
# ---------------------------------------------------------------------------


class AliasStore:
    """Durable map from Message-ID to the alias an inbound message arrived at.

    One row per (message-id, alias).  Rows age out after `retention_days`, so
    the store stays proportional to recent inbound mail.  Every method is
    fail-safe: a broken or read-only store disables the feature but never
    raises into the milter callback.
    """

    def __init__(self, path, retention_days):
        self.path = path
        self.retention = retention_days * 86400
        self._db = None
        self._broken = False
        self._lock = threading.Lock()
        self._last_prune = 0.0

    def _conn(self):
        if self._broken:
            return None
        if self._db is not None:
            return self._db
        try:
            parent = os.path.dirname(self.path)
            if parent:
                os.makedirs(parent, mode=0o700, exist_ok=True)
            # One process holds the connection.  The lock serialises access,
            # because libmilter may handle connections in more than one
            # thread.
            db = sqlite3.connect(self.path, timeout=5, check_same_thread=False)
            # A rollback journal, not WAL.  With WAL, a reader needs the
            # -shm index, and a second process did not always see the rows
            # the milter had committed.  Mail volume is low here, so the
            # extra fsync per message does not matter.
            db.execute("PRAGMA journal_mode=TRUNCATE")
            db.execute("PRAGMA synchronous=NORMAL")
            db.execute(
                "CREATE TABLE IF NOT EXISTS aliases ("
                " id INTEGER PRIMARY KEY,"
                " message_id TEXT NOT NULL,"
                " alias TEXT NOT NULL,"
                " created INTEGER NOT NULL)"
            )
            db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS aliases_message_id_alias"
                " ON aliases(message_id, alias)"
            )
            db.execute("CREATE INDEX IF NOT EXISTS aliases_created ON aliases(created)")
            db.commit()
            self._db = db
        except (OSError, sqlite3.Error) as exc:
            self._broken = True
            log.warning("alias store %s is unusable: %s", self.path, exc)
            return None
        return self._db

    def record(self, message_ids, aliases):
        """Remember that each message-id was delivered to each alias."""
        if not message_ids or not aliases:
            return
        db = self._conn()
        if db is None:
            return
        now = int(time.time())
        rows = [
            (mid.lower(), alias.lower(), now)
            for mid in message_ids[:_MAX_MESSAGE_IDS]
            for alias in aliases[:_MAX_RCPTS]
        ]
        try:
            with self._lock:
                db.executemany(
                    "INSERT OR IGNORE INTO aliases (message_id, alias, created)"
                    " VALUES (?, ?, ?)",
                    rows,
                )
                db.commit()
                self._prune(db, now)
        except sqlite3.Error as exc:
            log.warning("cannot record aliases: %s", exc)

    def _prune(self, db, now):
        """Delete rows older than the retention window, at most once an hour."""
        if now - self._last_prune < 3600:
            return
        self._last_prune = now
        db.execute("DELETE FROM aliases WHERE created < ?", (now - self.retention,))
        db.commit()

    def lookup(self, message_ids):
        """Yield stored aliases for each message-id, in the order recorded."""
        db = self._conn()
        if db is None:
            return
        for mid in message_ids[:_MAX_MESSAGE_IDS]:
            try:
                with self._lock:
                    cur = db.execute(
                        "SELECT alias FROM aliases WHERE message_id = ? ORDER BY id",
                        (mid.lower(),),
                    )
                    rows = cur.fetchall()
            except sqlite3.Error as exc:
                log.warning("cannot look up aliases: %s", exc)
                return
            for (alias,) in rows:
                yield alias


STORE = AliasStore(STATEFILE, RETENTION_DAYS)


# ---------------------------------------------------------------------------
# Authorisation: Postfix's own sender_login_maps
# ---------------------------------------------------------------------------


def is_authorized(login, target, vaccounts_map, postmap):
    """Return True if Postfix allows `login` to send from `target`.

    Postfix itself decides this at MAIL FROM time through
    `smtpd_sender_login_maps`.  That check has already run when this milter
    rewrites the sender at end-of-message, so the question is asked directly
    of the same table.  The two-step lookup mirrors Postfix: exact address
    first, then the `@domain` wildcard of a catch-all alias.
    """
    login = (login or "").strip().lower()
    if not vaccounts_map or not target or not login:
        return False
    local, _, domain = target.rpartition("@")
    candidates = [target]
    if local and domain:
        candidates.append("@" + domain)
    for cand in candidates:
        # Defence in depth: a key that starts with '-' must never reach a
        # command line parser.
        if not cand or cand.startswith("-") or any(c.isspace() for c in cand):
            continue
        try:
            out = subprocess.run(
                [postmap, "-q", cand, vaccounts_map],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode != 0:
            continue
        owners = [o.strip().lower() for o in out.stdout.replace(",", " ").split()]
        if login in owners:
            return True
    return False


# ---------------------------------------------------------------------------
# Signature / encryption detection (header only)
# ---------------------------------------------------------------------------

_SIGNED_ENCRYPTED_TYPES = frozenset(
    (
        "multipart/signed",
        "multipart/encrypted",
        "application/pkcs7-mime",
        "application/x-pkcs7-mime",
        "application/pgp-encrypted",
    )
)


def media_type(value):
    """Return the lowercased `type/subtype` of a Content-Type value, or None."""
    if not value:
        return None
    head = value.split(";", 1)[0].strip().lower()
    if "/" not in head or head.startswith("/") or head.endswith("/"):
        return None
    return head


def is_signed_or_encrypted(headers):
    """True if the message is cryptographically protected and must not be rewritten.

    A client-added DKIM-Signature means the client signed the message it
    built, so rewriting From would break that signature.  Our own DKIM
    signature is added later by rspamd, which runs after this milter.
    """
    for name, value in headers:
        n = name.lower()
        if n == "dkim-signature":
            return True
        if n.startswith("x-pgp-") or n.startswith("x-pkcs7") or n.startswith("x-smime"):
            return True
        if n == "content-type" and media_type(value) in _SIGNED_ENCRYPTED_TYPES:
            return True
    return False


# ---------------------------------------------------------------------------
# The milter
# ---------------------------------------------------------------------------


class ReplyAliasMilter(Base):
    def __init__(self):
        """Start a fresh connection with no per-message state."""
        Base.__init__(self)
        self.reset()

    def reset(self):
        self.login = None            # SASL login, set only for submission
        self.account = None          # primary address of an opted-in account
        self.sender = None
        self.recipients = []         # envelope recipients (inbound only)
        self.references = []         # In-Reply-To / References ids
        self.message_ids = []        # this message's own Message-ID headers
        self.headers = []
        self.from_value = None
        self.header_overflow = False

    # -- connection / auth ------------------------------------------------

    def connect(self, hostname, family, hostaddr):
        """Accept the SMTP connection (no action needed)."""
        return CONTINUE

    def envfrom(self, f, *rest):
        """Record the envelope sender; arm rewriting for opted-in accounts."""
        self.reset()
        try:
            self.sender = f
            auth = (self.getsymval("{auth_authen}") or "").strip().lower()
            self.login = auth or None
            if auth and auth in ACCOUNTS:
                self.account = ACCOUNTS[auth]
        except Exception:
            self.account = None
        return CONTINUE

    def envrcpt(self, to, *rest):
        """Collect inbound envelope recipients (the aliases) for the store."""
        # Only unauthenticated mail is inbound.  Mail from an authenticated
        # account, opted in or not, is the user's own mail and must not be
        # recorded as an alias.
        if self.login or not to:
            return CONTINUE
        try:
            if len(self.recipients) >= _MAX_RCPTS:
                return CONTINUE
            addr = safe_address(to)
            if addr:
                self.recipients.append(addr)
        except Exception:
            pass
        return CONTINUE

    def header(self, field, value):
        """Collect headers; keep Message-IDs and the first From header."""
        try:
            if isinstance(field, bytes):
                field = field.decode("ascii", "surrogateescape")
            if isinstance(value, bytes):
                value = value.decode("utf-8", "surrogateescape")
            if len(self.headers) >= _MAX_HEADERS:
                self.header_overflow = True
                return CONTINUE
            name = field.lower()
            self.headers.append((name, value))
            if name == "from" and self.from_value is None:
                self.from_value = value
            elif name == "message-id":
                # The message's own ID, needed on the inbound side only.
                self.message_ids.extend(extract_message_ids(value))
            elif name in ("in-reply-to", "references"):
                self.references.extend(extract_message_ids(value))
        except Exception:
            pass
        return CONTINUE

    def eoh(self):
        """End of headers: nothing to do here."""
        return CONTINUE

    def body(self, blk):
        """Pass body through unmodified (no body edits for this milter)."""
        return CONTINUE

    def eom(self):
        """Record the alias for inbound mail, or rewrite a reply's sender."""
        try:
            if self.account:
                return self._rewrite()
            if self.login:
                return CONTINUE
            return self._record()
        except Exception:
            # Fail open: a bug must never hold or refuse mail.
            _emit("error", "unexpected error; mail left untouched")
            return CONTINUE

    # -- inbound: remember message-id -> alias ----------------------------

    def _record(self):
        if self.header_overflow:
            _emit("skipped", "too many headers")
            return CONTINUE
        log.debug("inbound: ids=%s recipients=%s", self.message_ids, self.recipients)
        if not self.recipients or not self.message_ids:
            return CONTINUE
        aliases = [a for a in self.recipients if a.lower() not in PRIMARIES]
        if not aliases:
            return CONTINUE
        STORE.record(self.message_ids, aliases)
        log.debug("inbound: recorded %s -> %s", self.message_ids, aliases)
        return CONTINUE

    # -- outbound: rewrite a reply ---------------------------------------

    def _rewrite(self):
        if self.header_overflow:
            _emit("skipped", "too many headers")
            return CONTINUE
        # 1) Never touch signed/encrypted mail (would break signatures).
        if is_signed_or_encrypted(self.headers):
            _emit("skipped", "content-signed or encrypted")
            return CONTINUE
        # 2) Only replies are rewritten.
        if not self.references:
            _emit("skipped", "not a reply (no In-Reply-To/References)")
            return CONTINUE
        # 3) Only when the reply is sent from the account's primary address.
        #    An explicitly chosen From: identity wins over the alias.
        if not self.from_value:
            _emit("skipped", "no From header")
            return CONTINUE
        from_addr = safe_address(parseaddr(self.from_value)[1])
        if from_addr and from_addr.lower() != self.account.lower():
            _emit("skipped", "From is not the account primary")
            return CONTINUE

        # 4) Find the alias the original message was delivered to.
        target = self._target()
        if not target:
            _emit("skipped", "no recorded alias for this thread")
            return CONTINUE

        # 5) Rewrite.  chgfrom() changes the envelope sender (Return-Path);
        #    chgheader() replaces the From: header, keeping any display name.
        try:
            self.chgfrom("<" + target + ">")
            self._rewrite_from(target)
            _emit("rewrote", "sender %s -> %s" % (_log_safe(self.sender, 120), target))
        except Exception:
            _emit("error", "rewrite failed; mail left untouched")
        return CONTINUE

    def _target(self):
        """Return the first stored alias that this account may send from."""
        seen = set()
        for mid in self.references:
            if mid in seen or not is_safe_msgid(mid):
                continue
            seen.add(mid)
            if len(seen) > _MAX_MESSAGE_IDS:
                break
            for alias in STORE.lookup([mid]):
                candidate = safe_address(alias)
                if not candidate:
                    continue
                if candidate.lower() == self.account.lower():
                    continue
                if not is_authorized(self.login, candidate, VACCOUNTS_MAP, POSTMAP):
                    continue
                return candidate
        return None

    def _rewrite_from(self, target):
        """Replace the From header with target, keeping the display name."""
        name = parseaddr(self.from_value or "")[0]
        self.chgheader("From", 0, format_address(name, target))


# -- registration -----------------------------------------------------------

Milter.factory = ReplyAliasMilter
# pymilter answers a callback exception with TEMPFAIL by default, which makes
# Postfix hold or refuse the mail.  This milter must fail open instead.
Milter.set_exception_policy(CONTINUE)

if __name__ == "__main__":
    runmilter("reply-alias", SOCKET)
