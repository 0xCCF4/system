#!/usr/bin/env python3
"""reply-alias-milter

A Postfix milter that rewrites the envelope sender and From: header of an
outbound (authenticated submission) *reply* to the alias the original message
was delivered to.

How it works
------------
The reply carries the original message's Message-ID in its In-Reply-To: /
References: headers.  We find that original message in the authenticated
user's Maildir, read its X-Original-To: header (Postfix writes it via the LMTP
`flags=O` transport), and - if the authenticated account is authorised to send
from that address (queried against Postfix's own `vaccounts` sender-login map) -
we rewrite the reply to send from that alias.

Safeguards
----------
* Only acts on SASL-authenticated submission (never inbound port-25 mail).
* Only rewrites to addresses the Postfix `sender_login_maps` authorises for
  the authenticated account (queried via `postmap`).
* Skips signing/encryption wrappers (PGP/S/MIME, DKIM) - we never break a
  signature by rewriting From/envelope.
* Fail-open: any lookup error simply leaves the message untouched.
"""

import logging
import os
import re
import subprocess
import sys

from Milter import Base, Milter, runmilter, CONTINUE

# Debug logging goes to stderr, which systemd routes to the journal.  You can
# watch it live with:
#   journalctl -u reply-alias-milter -f
# and toggle verbosity by setting the NixOS option (debug = true) and
# restarting the service.
log = logging.getLogger("reply-alias")
_RUNNING = {}


def setup_logging(debug):
    """Configure stderr logging once; debug toggles level and detail."""
    if _RUNNING:
        return
    _RUNNING["yes"] = True
    level = logging.DEBUG if debug else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    # Mirror the milter's identity in every line so the two milters are
    # easy to separate in the journal.
    handler.setFormatter(logging.Formatter("%(name)s %(levelname)s: %(message)s"))
    log.addHandler(handler)
    log.setLevel(level)
    log.propagate = False

# ---------------------------------------------------------------------------
# Configuration (read from the NixOS-generated config file)
# ---------------------------------------------------------------------------

# The NixOS module renders the config as an immutable store file and points
# REPLY_ALIAS_CONFIG at it (see mailReplyAlias.nix).  Reading it from the
# store means the milter never needs to write any config at runtime, which is
# what lets it run unprivileged instead of as root.  Keep /etc/reply-alias.conf
# as a fallback for manual setups; a missing file degrades to a no-op.
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
    except OSError:
        # Missing/unreadable config: start as a harmless no-op rather than crash.
        pass
    return cfg


CONFIG = load_config()

SOCKET = CONFIG.get("socket", "/run/reply-alias/reply-alias.sock")
STORAGE_ROOT = CONFIG.get("storage")
VACCOUNTS_MAP = CONFIG.get("vaccountsmap")
POSTMAP = CONFIG.get("postmap", "/run/current-system/sw/bin/postmap")
DEBUG = CONFIG.get("debug", "0") in ("1", "true", "yes", "on")

setup_logging(DEBUG)

log.debug("reply-alias milter starting (debug on)")
log.debug("socket=%s storage=%s vaccounts=%s", SOCKET, STORAGE_ROOT, VACCOUNTS_MAP)

# Accounts that have opted in to reply-alias rewriting:
#   account-login -> { "primary": str }
# The set of aliases each account may reply as is NOT listed here; it is
# resolved at runtime from Postfix's vaccounts sender-login map.
ACCOUNTS = {}
for key, value in CONFIG.items():
    if key.startswith("account."):
        # account.postmaster@example.com = postmaster@example.com
        login = key.split(".", 1)[1]
        ACCOUNTS[login] = {"primary": value}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# A token is anything inside <...>, which is how Message-IDs appear in
# In-Reply-To / References.  Leading dots (dot-unstuffing) are stripped.
_MID_RE = re.compile(r"<([^<>]*)>")


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
# Sanitizers
# ---------------------------------------------------------------------------
# Every value that reaches a boundary (a subprocess argument, a path, or an
# address written back into mail) is validated against its real grammar before
# it is used.  A value that fails is dropped (fail open): the message is left
# untouched rather than rewritten with bad data.

# A safe Message-ID consists of dot-atom characters only.  It may never contain
# whitespace, control characters, or angle brackets.
_SAFE_DOT_ATOM = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!"
                       "#$%&'*+-/=?^_`{|}~.")

# A real Message-ID is at least a few chars long.  Any shorter token found in
# an In-Reply-To / References header is almost certainly not a conforming ID and
# would only risk a false (substring) match against a stored message, so it is
# dropped.
_MIN_MSGID_LEN = 8


def is_safe_msgid(mid):
    """True if `mid` looks like a real Message-ID (id-left@id-right, dot-atom).

    Note: `extract_message_ids` deliberately grabs any `<...>` token it sees in
    In-Reply-To / References, because that is where conforming Message-IDs sit.
    A hostile sender can put arbitrary text there, so this is the gate that
    rejects junk before it becomes a grep argument or a matcher key.  A Message-
    ID's two halves (id-left, id-right) are each dot-atom, separated by @; the
    @ itself is not a dot-atom character.
    """
    if not mid or len(mid) < _MIN_MSGID_LEN or len(mid) > 998:
        return False
    left, sep, right = mid.partition("@")
    if not sep or not left or not right or "@" in right:
        return False
    return all(c in _SAFE_DOT_ATOM for c in left) and all(c in _SAFE_DOT_ATOM for c in right)


# A rewritten address must be a real, well-formed email address: a dot-atom
# local part and a hostname/domain part that contains no whitespace, control
# characters, angle brackets, or quotes.  This is the value that is written
# back into the envelope and the From header, so header/form-amalgamation
# injection is prevented here.
_EMAIL_RE = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
)


def safe_address(value):
    """
    Return `value` as a bare validated email address, or None if invalid.
    Accepts an optional surrounding `<...>` (as written by Postfix delivery).
    Rejects any value containing whitespace, control characters, or other
    header-breaking characters.
    """
    if not value:
        return None
    v = value.strip()
    if v.startswith("<") and v.endswith(">"):
        v = v[1:-1]
    # No whitespace or control characters anywhere in the address.
    if any(c.isspace() or ord(c) < 0x20 or ord(c) == 0x7F for c in v):
        return None
    if not _EMAIL_RE.match(v):
        return None
    return v


def safe_display_name(name):
    """
    Return `name` with any character that could break the From header removed.
    `name` is the display part reconstructed from the reply's From header, so
    it is attacker-controlled and may not carry CR/LF or other control
    characters into the rewritten header.
    """
    if not name:
        return ""
    return "".join(c for c in name if ord(c) >= 0x20 and c not in "\r\n")


def safe_log(text):
    """Strip control characters so an attacker-controlled value (headers,
    envelope sender, stored header values) cannot inject fake lines into the
    journal.  Keeps printable characters and tab only."""
    if not text:
        return ""
    return "".join(c for c in text if c == "\t" or (ord(c) >= 0x20 and ord(c) != 0x7F))


def safe_log_list(items):
    """Apply safe_log to every item of a list and return the sanitized list."""
    return [safe_log(i) for i in items]


def _safe_component(comp):
    """True if `comp` is a plain dot-atom path component (no traversal)."""
    return bool(comp) and comp not in (".", "..") and all(
        c in _SAFE_DOT_ATOM and c not in "/\\" for c in comp
    )


def maildir_for_login(storage_root, login):
    """Return the Maildir path for a login like user@example.com."""
    if "@" not in login:
        return None
    user, _, domain = login.rpartition("@")
    # Only plain dot-atom components, no path separators or traversal.
    if not (_safe_component(user) and _safe_component(domain)):
        return None
    # Dovecot layout: ~/mail under home = <storage>/<domain>/<username>
    return os.path.join(storage_root, domain, user, "mail")


def _is_within(root, path):
    """True if the real path `path` stays inside `root` (no escape)."""
    root_real = os.path.realpath(root)
    path_real = os.path.realpath(path)
    return path_real == root_real or path_real.startswith(root_real + os.sep)


_SIGNED_ENCRYPTED_CTS = (
    "multipart/signed",
    "multipart/encrypted",
    "application/pkcs7-mime",      # S/MIME signed-data or enveloped-data
    "application/pkcs7-signature",  # detached S/MIME signature
    "application/x-pkcs7-mime",
    "application/x-pkcs7-signature",
    "application/pgp-encrypted",
    "application/pgp-signature",
)


def is_signed_or_encrypted(headers):
    """
    Detect top-level signing/encryption indicators purely from headers.  This
    is cheap and runs before any Maildir lookup.  Returns True if the message
    is cryptographically protected and must not be rewritten.
    """
    for name, value in headers:
        n = name.lower()
        if n == "dkim-signature":
            return True  # already signed (e.g. client-added)
        if n.startswith("x-pgp-") or n.startswith("x-pkcs7") or n.startswith("x-smime"):
            return True
        if n == "content-type":
            v = value.lower()
            if any(ct in v for ct in _SIGNED_ENCRYPTED_CTS):
                return True
    return False


def find_original_recipient(maildir, message_ids):
    """
    Search the Maildir for a stored message whose Message-ID matches one of the
    given ids and return the X-Original-To: address from that message.
    Returns the first match's X-Original-To, or None.
    """
    for sub in ("cur", "new"):
        d = os.path.join(maildir, sub)
        if not os.path.isdir(d):
            continue
        for mid in message_ids:
            # Drop malformed Message-IDs before they reach grep or the matcher.
            if not is_safe_msgid(mid):
                continue
            # Probe quickly with grep -rl; only read files that contain the id.
            # Fail open: any error (timeout, missing binary) is treated as "no
            # match" so a milter hiccup never blocks or fails mail.
            try:
                probe = subprocess.run(
                    ["grep", "-rl", "-F", mid, "--", d],
                    capture_output=True,
                    text=True,
                    timeout=300,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if probe.returncode == 1:  # no match
                continue
            for path in probe.stdout.splitlines():
                if not path:
                    continue
                # Only ever open files that stay inside this Maildir.
                if not _is_within(maildir, path):
                    continue
                recip = _x_original_to(path, mid)
                if recip:
                    return recip
    return None


def _x_original_to(path, mid):
    """Read one message file; return X-Original-To if its Message-ID matches mid."""
    try:
        with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
            found_mid = False
            recip = None
            for raw in fh:
                line = raw.rstrip("\r\n")
                if line == "":
                    # End of headers; the rest is the (possibly huge) body.
                    break
                low = line.lower()
                if low.startswith("x-original-to:"):
                    recip = line.split(":", 1)[1].strip()
                elif low.startswith("message-id:"):
                    # Compare the Message-ID of this stored message to the id we
                    # seek, exactly and case-insensitively.  A raw substring
                    # match ("mid in val") would let a short or partial token
                    # hit the body of an unrelated, longer Message-ID.
                    val = line.split(":", 1)[1].strip()
                    if mid.lower() in (i.lower() for i in extract_message_ids(val)):
                        found_mid = True
            if found_mid and recip:
                return recip
    except OSError:
        pass
    return None


def is_authorized(login, target, vaccounts_map, postmap):
    """
    Ask Postfix itself (its `sender_login_maps` vaccounts table) whether the
    authenticated account `login` may send from `target`.  Returns bool.

    We mirror Postfix's two-step sender_login_maps lookup: exact address, then
    `@domain`.  The target is authorised only if the owning account(s) returned
    include `login`.
    """
    if not vaccounts_map or not target:
        return False
    local, _, domain = target.rpartition("@")
    candidates = [target]
    if local and domain:
        candidates.append("@" + domain)  # domain wildcard (catch-all alias)
    for cand in candidates:
        try:
            out = subprocess.run(
                [postmap, "-q", cand, vaccounts_map],
                capture_output=True,
                text=True,
                timeout=15,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode == 0:
            owners = [o.strip() for o in out.stdout.replace(",", " ").split()]
            if login in owners:
                return True
    return False


# ---------------------------------------------------------------------------
# The milter
# ---------------------------------------------------------------------------

class ReplyAliasMilter(Base):
    def __init__(self):
        """Reset per-message state for a new connection."""
        Base.__init__(self)
        self.active = False          # is this a message we may rewrite?
        self.authenticated_user = None
        self.sender = None
        self.headers = []
        self.message_ids = []
        self.original_from = None

    # -- connection / auth ------------------------------------------------

    def connect(self, hostname, family, hostaddr):
        """Accept the SMTP connection (no action needed)."""
        return CONTINUE

    def envfrom(self, f, *rest):
        """Record the envelope sender; arm rewriting for authenticated, opted-in accounts (outbound only)."""
        self.sender = f
        auth = self.getsymval("{auth_authen}") or ""
        self.authenticated_user = auth
        # Only rewrite authenticated submissions from an opted-in account.
        self.active = bool(auth) and auth in ACCOUNTS
        log.debug(
            "envfrom sender=%r auth_authen=%r active=%s", safe_log(f), auth, self.active)
        if not self.active:
            return CONTINUE
        # (Re)initialise per-message state up front.
        self.headers = []
        self.message_ids = []
        self.original_from = None
        return CONTINUE

    def envrcpt(self, to, *rest):
        """Accept every recipient (rewriting is done at end of message)."""
        return CONTINUE

    def header(self, field, value):
        """Collect headers; remember In-Reply-To/References ids and the From header."""
        if not self.active:
            return CONTINUE
        # pymilter passes the header name as bytes and the decoded value as str;
        # be defensive and normalise both in case they arrive as raw bytes.
        if isinstance(field, bytes):
            field = field.decode("ascii", errors="surrogateescape")
        if isinstance(value, bytes):
            value = value.decode("utf-8", errors="surrogateescape")
        name = field.lower()
        self.headers.append((name, value))
        if name == "in-reply-to":
            self.message_ids.extend(extract_message_ids(value))
        elif name == "references":
            self.message_ids.extend(extract_message_ids(value))
        elif name == "from":
            self.original_from = value
            log.debug("From header: %r", safe_log(value))
        return CONTINUE

    def eoh(self):
        """End of headers: nothing to do here."""
        return CONTINUE

    def body(self, blk):
        """Pass body through unmodified (no body edits for this milter)."""
        return CONTINUE

    def eom(self):
        """Find the reply's original recipient and rewrite envelope/From to the alias."""
        if not self.active:
            return CONTINUE

        # 1) Never touch signed/encrypted mail (would break signatures).
        if is_signed_or_encrypted(self.headers):
            log.info("skip: message is signed/encrypted")
            return CONTINUE

        # 2) Only replies are rewritten.
        if not self.message_ids:
            log.info("skip: no In-Reply-To/References (not a reply)")
            return CONTINUE
        log.debug("reply msgids: %s", safe_log_list(self.message_ids))

        account = ACCOUNTS[self.authenticated_user]
        primary = account["primary"]

        # 3) Find the original recipient in the user's Maildir.
        maildir = maildir_for_login(STORAGE_ROOT, self.authenticated_user)
        if not maildir:
            log.info("skip: no maildir for %s", self.authenticated_user)
            return CONTINUE
        target = find_original_recipient(maildir, self.message_ids)
        if not target:
            log.info("skip: original message not found in %s", maildir)
            return CONTINUE
        log.debug("original recipient (raw): %r", safe_log(target))

        # The X-Original-To value is user-controlled (read from a stored
        # message).  It must be a well-formed address before it is validated
        # by postmap or written back into the envelope and From header.
        target = safe_address(target)
        if not target:
            log.info("skip: original recipient is not a valid address")
            return CONTINUE

        # 4) Never rewrite to the user's own primary address or to the address
        #    the client already used (the reply's From address).
        if target.lower() == primary.lower():
            log.info("skip: target %s is the account primary", target)
            return CONTINUE
        # Pull the bare address out of the reply's From header, then compare.
        from_raw = self.original_from or ""
        if "<" in from_raw:
            from_addr = from_raw.partition("<")[2].partition(">")[0]
        else:
            from_addr = from_raw
        if safe_address(from_addr) and target.lower() in safe_address(from_addr).lower():
            log.info("skip: target %s already in From (%s)", target, safe_log(from_addr))
            return CONTINUE

        # 5) Authorisation: the account must be permitted to send from target,
        #    as decided by Postfix's own sender_login_maps (vaccounts).
        if not is_authorized(self.authenticated_user, target, VACCOUNTS_MAP, POSTMAP):
            log.info("skip: %s not authorised for %s (vaccounts)",
                     self.authenticated_user, target)
            return CONTINUE

        # 6) Rewrite. chgfrom() changes the envelope sender (Return-Path);
        #    chgheader() replaces the From: header, preserving any display name.
        try:
            self.chgfrom("<" + target + ">")
            self._rewrite_from(self.original_from, target)
            log.info("rewrote sender: %s -> %s", safe_log(self.sender), target)
        except Exception:
            log.exception("rewrite failed; leaving mail untouched")
            return CONTINUE
        return CONTINUE

    def _rewrite_from(self, original_from, target):
        """Replace the From header with target, preserving the display name if present."""
        # `original_from` is user-controlled; strip any character that could
        # break the From header before rebuilding the value.
        display = safe_display_name(
            original_from.partition("<")[0] if original_from else ""
        )
        if original_from and original_from.partition("<")[2].endswith(">"):
            return self.chgheader("From", 0, display.rstrip() + " <" + target + ">")
        return self.chgheader("From", 0, target)


# -- registration -----------------------------------------------------------

# Point pymilter's connection factory at our class.
Milter.factory = ReplyAliasMilter

if __name__ == "__main__":
    runmilter("reply-alias", SOCKET)
