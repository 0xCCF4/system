#!/usr/bin/env python3
"""mail-service-tag milter

A Postfix milter that prefixes the recipient's service tag (e.g. `[github]`)
onto the Subject line of *inbound* mail that is NOT signed or encrypted with
S/MIME or PGP.  The idea: the postmaster has catch-all aliases, so everything
addressed to `service@yourdomain` lands in one inbox.  Verified (content-
signed) mail keeps a clean Subject; everything else gets the `[service]` tag
so it stands out as not from the real service.

How it works
------------
At delivery time Postfix runs the configured milters.  This one:
* only acts on inbound (non authenticated submission) mail, so it never tags
  mail the user sends themselves;
* reads the envelope recipients (`envrcpt`); for any recipient whose
  local-part is in the `services` map it remembers the tag;
* at end-of-message, if the message is not S/MIME/PGP signed (checked against
  its own headers) and the Subject is not already tagged with that tag, it
  prepends `[<tag>] ` to the Subject.

Safeguards
----------
* Only tags inbound mail, never authenticated submission.
* Never tags mail that is content-signed (S/MIME or PGP) - those are assumed
  to be genuine.
* Skips rewriting if the Subject already starts with the same `[tag]`, so a
  re-run cannot double-prefix.
* Fail-open: any error leaves the message untouched, never blocks delivery.
"""

import logging
import os
import re
import sys

from Milter import Base, Milter, runmilter, CONTINUE

log = logging.getLogger("mail-service-tag")
_RUNNING = {}


def setup_logging(debug):
    """Configure stderr logging once (systemd routes stderr to the journal)."""
    if _RUNNING:
        return
    _RUNNING["yes"] = True
    level = logging.DEBUG if debug else logging.INFO
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(name)s %(levelname)s: %(message)s"))
    log.addHandler(handler)
    log.setLevel(level)
    log.propagate = False


# Config lives in an immutable NixOS store file rendered by mailServiceTag.nix.
CONFIG_PATH = os.environ.get("SERVICE_TAG_CONFIG", "/etc/mail-service-tag.conf")


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
        pass
    return cfg


CONFIG = load_config()
DEBUG = CONFIG.get("debug", "0") in ("1", "true", "yes", "on")
SOCKET = CONFIG.get("socket", "/run/mail-service-tag/mail-service-tag.sock")

# Explicit service -> tag mapping.  Keys are recipient local-parts; values are
# the tag placed in the Subject, e.g. `github = github` -> `[github]`.
SERVICES = {}
for key, value in CONFIG.items():
    if key.startswith("service."):
        localpart = key.split(".", 1)[1]
        SERVICES[localpart.lower()] = value

setup_logging(DEBUG)
log.debug("mail-service-tag milter starting (debug on)")
log.debug("socket=%s services=%s", SOCKET, sorted(SERVICES))


# -- signature / encryption detection (header only) --------------------------

_SIGNED_ENCRYPTED_CTS = (
    "multipart/signed",
    "multipart/encrypted",
    "application/pkcs7-mime",
    "application/pkcs7-signature",
    "application/x-pkcs7-mime",
    "application/x-pkcs7-signature",
    "application/pgp-encrypted",
    "application/pgp-signature",
)


def is_signed_or_encrypted(headers):
    """True if the top-level headers indicate S/MIME or PGP signing/encryption."""
    for name, value in headers:
        n = name.lower()
        if n == "dkim-signature":
            return True
        if n.startswith("x-pgp-") or n.startswith("x-pkcs7") or n.startswith("x-smime"):
            return True
        if n == "content-type":
            v = value.lower()
            if any(ct in v for ct in _SIGNED_ENCRYPTED_CTS):
                return True
    return False


_TAG_RE = re.compile(r"^\[[^\]\r\n]+\]\s*")


def _log_safe(text):
    """Strip control characters so an attacker-controlled value cannot inject
    fake lines into the journal.  Keeps printable characters only."""
    if not text:
        return ""
    return "".join(c for c in text if c == "\t" or (ord(c) >= 0x20 and ord(c) != 0x7F))


def _strip_existing_tag(subject, tag):
    """Return (already_tagged, stripped_subject): whether this exact `[tag]`
    prefix is already present, and the subject with any [..] prefix removed."""
    text = subject or ""
    if text.lower().startswith(("[%s]" % tag).lower()):
        return True, text[len("[%s]" % tag):].lstrip()
    # A different [foo] prefix: keep it (do not double-prefix with another tag).
    return False, text


class ServiceTagMilter(Base):
    def __init__(self):
        """Reset per-message state for a new connection."""
        Base.__init__(self)
        self.active = False
        self.tags = []        # tags collected from matched recipients
        self.subject = None
        self.headers = []

    def connect(self, hostname, family, hostaddr):
        """Accept the SMTP connection (no action needed)."""
        return CONTINUE

    def envfrom(self, f, *rest):
        """Arm tagging only for inbound mail (unauthenticated, not the user's own submissions)."""
        # Tag only inbound (unauthenticated) mail.  Authenticated submission is
        # the user sending mail out; it must not be tagged.
        auth = self.getsymval("{auth_authen}") or ""
        self.active = not bool(auth)
        self.tags = []
        self.subject = None
        self.headers = []
        log.debug("envfrom sender=%r auth_authen=%r active=%s", _log_safe(f), auth, self.active)
        return CONTINUE

    def envrcpt(self, to, *rest):
        """Collect tags for recipients whose local-part is in the services map."""
        if not self.active or not to:
            return CONTINUE
        # `to` may be a plain address or <...>-wrapped; take the local part.
        addr = to.strip()
        if addr.startswith("<") and addr.endswith(">"):
            addr = addr[1:-1]
        local, _, domain = addr.rpartition("@")
        key = local.lower()
        tag = SERVICES.get(key)
        if tag:
            self.tags.append(tag)
            log.debug("recipient %s matched service %s (tag %s)", _log_safe(to), key, tag)
        else:
            log.debug("recipient %s not in service map", _log_safe(to))
        return CONTINUE

    def header(self, field, value):
        """Collect headers; remember the Subject header."""
        if not self.active:
            return CONTINUE
        if isinstance(field, bytes):
            field = field.decode("ascii", errors="surrogateescape")
        if isinstance(value, bytes):
            value = value.decode("utf-8", errors="surrogateescape")
        name = field.lower()
        self.headers.append((name, value))
        if name == "subject":
            self.subject = value
        return CONTINUE

    def eoh(self):
        """End of headers: nothing to do here."""
        return CONTINUE

    def body(self, blk):
        """Pass body through unmodified (no body edits for this milter)."""
        return CONTINUE

    def eom(self):
        """Prepend [<tag>] to the Subject of unsigned inbound mail for matched recipients."""
        if not self.active:
            return CONTINUE
        if not self.tags:
            return CONTINUE
        # Never tag a message that is content-signed/encrypted.
        if is_signed_or_encrypted(self.headers):
            log.info("skip: message is S/MIME or PGP signed/encrypted")
            return CONTINUE

        tag = self.tags[0]
        # An empty or missing Subject is still tagged: write just [TAG] with no
        # content after it.  A non-empty Subject gets [TAG] <subject>.
        current = self.subject or ""
        already, _ = _strip_existing_tag(current, tag)
        if already:
            log.debug("skip: subject already tagged [%s]", tag)
            return CONTINUE
        new_subject = "[%s] %s" % (tag, current) if current else "[%s]" % tag
        try:
            self.chgheader("Subject", 0, new_subject)
            log.info("tagged subject: %r -> %r", _log_safe(self.subject), _log_safe(new_subject))
        except Exception:
            log.exception("failed to tag subject; leaving untouched")
            return CONTINUE
        return CONTINUE


Milter.factory = ServiceTagMilter

if __name__ == "__main__":
    runmilter("mail-service-tag", SOCKET)
