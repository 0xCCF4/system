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

import os
import re
import subprocess
import sys

from Milter import Base, Milter, runmilter, CONTINUE

# ---------------------------------------------------------------------------
# Configuration (read from the NixOS-generated config file)
# ---------------------------------------------------------------------------

CONFIG_PATH = "/etc/reply-alias.conf"


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


def maildir_for_login(storage_root, login):
    """Return the Maildir path for a login like user@example.com."""
    if "@" not in login:
        return None
    user, _, domain = login.rpartition("@")
    # Dovecot layout: ~/mail under home = <storage>/<domain>/<username>
    return os.path.join(storage_root, domain, user, "mail")


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
            # Probe quickly with grep -rl; only read files that contain the id.
            probe = subprocess.run(
                ["grep", "-rl", "-F", mid, "--", d],
                capture_output=True,
                text=True,
                timeout=30,
            )
            if probe.returncode == 1:  # no match
                continue
            for path in probe.stdout.splitlines():
                if not path:
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
                    # Compare the Message-ID of this stored message to the id we seek.
                    val = line.split(":", 1)[1].strip()
                    if mid in extract_message_ids(val) or mid in val:
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
        Base.__init__(self)
        self.active = False          # is this a message we may rewrite?
        self.authenticated_user = None
        self.sender = None
        self.headers = []
        self.message_ids = []
        self.original_from = None

    # -- connection / auth ------------------------------------------------

    def connect(self, hostname, family, hostaddr):
        return CONTINUE

    def envfrom(self, f, *rest):
        self.sender = f
        auth = self.getsymval("{auth_authen}") or ""
        self.authenticated_user = auth
        # Only rewrite authenticated submissions from an opted-in account.
        self.active = bool(auth) and auth in ACCOUNTS
        if not self.active:
            return CONTINUE
        # (Re)initialise per-message state up front.
        self.headers = []
        self.message_ids = []
        self.original_from = None
        return CONTINUE

    def envrcpt(self, to, *rest):
        return CONTINUE

    def header(self, field, value):
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
        return CONTINUE

    def eoh(self):
        return CONTINUE

    def body(self, blk):
        return CONTINUE

    def eom(self):
        if not self.active:
            return CONTINUE

        # 1) Never touch signed/encrypted mail (would break signatures).
        if is_signed_or_encrypted(self.headers):
            return CONTINUE

        # 2) Only replies are rewritten.
        if not self.message_ids:
            return CONTINUE

        account = ACCOUNTS[self.authenticated_user]
        primary = account["primary"]

        # 3) Find the original recipient in the user's Maildir.
        maildir = maildir_for_login(STORAGE_ROOT, self.authenticated_user)
        if not maildir:
            return CONTINUE
        target = find_original_recipient(maildir, self.message_ids)
        if not target:
            return CONTINUE

        # 4) Never rewrite to the user's own primary address or to the address
        #    the client already used.
        if target.lower() == primary.lower():
            return CONTINUE
        if self.original_from and target.lower() in self.original_from.lower():
            return CONTINUE

        # 5) Authorisation: the account must be permitted to send from target,
        #    as decided by Postfix's own sender_login_maps (vaccounts).
        if not is_authorized(self.authenticated_user, target, VACCOUNTS_MAP, POSTMAP):
            return CONTINUE

        # 6) Rewrite. chgfrom() changes the envelope sender (Return-Path);
        #    chgheader() replaces the From: header, preserving any display name.
        try:
            self.chgfrom("<" + target + ">")
            self._rewrite_from(self.original_from, target)
        except Exception:  # pragma: no cover - never block mail on our error
            return CONTINUE
        return CONTINUE

    def _rewrite_from(self, original_from, target):
        """Replace the From: header value with target, preserving a display name."""
        if original_from:
            name, _, addr = original_from.partition("<")
            if addr.endswith(">"):
                display = name.rstrip()
                return self.chgheader("From", 0, display + " <" + target + ">")
        return self.chgheader("From", 0, target)


# -- registration -----------------------------------------------------------

# Point pymilter's connection factory at our class.
Milter.factory = ReplyAliasMilter

if __name__ == "__main__":
    runmilter("reply-alias", SOCKET)
