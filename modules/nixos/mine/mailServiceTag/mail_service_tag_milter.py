#!/usr/bin/env python3
"""mail-service-tag milter

A Postfix milter that prefixes the recipient's service tag (for example
`[github]`) onto the Subject of *inbound* mail that is NOT signed or
encrypted with S/MIME or PGP.  The idea: the postmaster has catch-all
aliases, so everything addressed to `service@yourdomain` lands in one inbox.
Mail that claims a content signature keeps a clean Subject.  Everything else
gets the `[service]` tag, so it stands out as probably not from the real
service.

How it works
------------
At delivery time Postfix runs the configured milters.  This one:

* acts only on inbound (unauthenticated) mail, so it never tags mail the user
  sends themselves;
* records the envelope recipients (`envrcpt`).  If any recipient local-part
  is in the `services` map, it remembers that tag;
* at end-of-message, if the message does not claim an S/MIME or PGP signature
  and the Subject does not already start with the same tag, it prepends
  `[<tag>] ` to the Subject.

Safeguards
----------
* Only tags inbound mail, never authenticated submission.
* Skips mail that claims a content signature (S/MIME or PGP).
* Skips rewriting if the Subject already starts with the same tag, so a
  re-run cannot double-prefix.
* Removes CR, LF and other control characters from the tag and the Subject
  before it writes the header back, so hostile header content cannot break
  out of the Subject field.
* Bounds the header count and the written length, so one message cannot make
  the milter allocate or emit an unbounded amount.
* Fail-open: any error, including an unexpected exception, leaves the message
  untouched and never blocks delivery.

Limitation
----------
Signature detection reads headers only, because a milter cannot verify an
S/MIME or PGP signature without the sender's key material.  Any sender can
declare `Content-Type: multipart/signed` and so suppress the tag.  The tag is
a convenience, not a security boundary.
"""

import logging
import os
import re
import sys

import Milter

# The milter hook API.  Note the import style: `Milter` must stay the module.
# Assigning `Milter.factory` on the `Milter.Milter` class instead of on the
# package module leaves the default no-op class in place, and then every
# message passes through untouched without any error.
Base = Milter.Base
CONTINUE = Milter.CONTINUE
runmilter = Milter.runmilter

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


# One line per message, never one line per event.
_LOG_MAX = 300


def _emit(status, detail=""):
    """Write one status line for a message to stderr and flush it immediately.

    Every line starts with the milter name so the two milters are easy to
    separate in the journal.  The detail is attacker-influenced, so it is
    stripped of control characters and cut to a fixed length.
    """
    line = "mail-service-tag: %s" % _log_safe(status, 80)
    if detail:
        line += ": %s" % _log_safe(detail, _LOG_MAX)
    sys.stderr.write(line + "\n")
    sys.stderr.flush()


# -- value cleaning ---------------------------------------------------------

_CTL_RE = re.compile(r"[\x00-\x1f\x7f]+")


def _clean_header_value(value):
    """Return `value` with control characters replaced by spaces.

    A header value from libmilter can carry CR, LF and other control
    characters, and this value is written back into the Subject.  Anything
    below 0x20 or 0x7f is therefore removed.  Tabs and the CRLF of a folded
    header become a space, which is what unfolding means.
    """
    if not value:
        return ""
    return _CTL_RE.sub(" ", value).strip()


def _log_safe(text, limit):
    """Strip control characters from a value bound for the journal, and cut
    it to `limit` characters.  A hostile Subject can otherwise inject fake
    journal lines or flood the journal."""
    if not text:
        return ""
    clean = "".join(c for c in text if c == "\t" or (ord(c) >= 0x20 and ord(c) != 0x7F))
    return clean[:limit]


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
    except OSError as exc:
        # Missing or unreadable config: keep running as a harmless no-op, but
        # say so once at startup.  Otherwise nothing in the journal shows why
        # no mail is being tagged.
        _emit("error", "cannot read config %s: %s; tagging is off" % (path, exc))
    return cfg


CONFIG = load_config()
DEBUG = CONFIG.get("debug", "0") in ("1", "true", "yes", "on")
SOCKET = CONFIG.get("socket", "/run/mail-service-tag/mail-service-tag.sock")

# Explicit service -> tag mapping.  Keys are recipient local-parts.  Values
# are the tag placed in the Subject, so `github = github` yields `[github]`.
SERVICES = {}
for key, value in CONFIG.items():
    if key.startswith("service."):
        localpart = key.split(".", 1)[1].strip().lower()
        clean = _clean_header_value(value)
        if localpart and clean:
            SERVICES[localpart] = clean

setup_logging(DEBUG)
log.debug("mail-service-tag milter starting (debug on)")

# Upper bound on stored headers.  Only the Subject and the Content-Type
# matter, but the signature check also looks at X- headers.  A message with
# more headers than this is not tagged: it is almost certainly an attack
# rather than mail.
_MAX_HEADERS = 2000

# RFC 5322 limits a header line to 998 characters.  Keep the rewritten
# Subject below that, because Postfix folds long headers itself.
_MAX_SUBJECT = 900


# -- signature / encryption detection (header only) --------------------------

# Top-level media types that carry an S/MIME or PGP signature or ciphertext.
# Only the media type counts, not parameters: a sender must not be able to
# suppress the tag by putting `multipart/signed` into a `name=` parameter.
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
    """True if the top-level headers indicate S/MIME or PGP signing/encryption.

    Note: a DKIM-Signature header is deliberately NOT treated as signing.  DKIM
    covers only a subset of headers plus the body and does not prove who wrote
    the content, so it must not suppress the [service] tag.  Almost all real
    inbound mail is DKIM-signed.
    """
    for name, value in headers:
        n = name.lower()
        if n.startswith("x-pgp-") or n.startswith("x-pkcs7") or n.startswith("x-smime"):
            return True
        if n == "content-type" and media_type(value) in _SIGNED_ENCRYPTED_TYPES:
            return True
    return False


def _has_tag_prefix(subject, tag):
    """True if `subject` already starts with this exact `[tag]` (any case)."""
    text = subject or ""
    return text.lower().startswith(("[%s]" % tag).lower())


def _tagged_subject(subject, tag):
    """Return the Subject with `[tag] ` in front, kept within the size limit.

    The tag always goes in front, even when the Subject starts with a
    different `[something]` prefix.  Skipping in that case would let a sender
    hide a forged message by writing a bracket at the start of the Subject.
    """
    subject = _clean_header_value(subject)
    prefix = "[%s] " % tag
    if not subject:
        return "[%s]" % tag
    while subject and len((prefix + subject).encode("utf-8", "replace")) > _MAX_SUBJECT:
        subject = subject[:-1]
    return (prefix + subject) if subject else "[%s]" % tag


class ServiceTagMilter(Base):
    def __init__(self):
        """Reset per-message state for a new connection."""
        Base.__init__(self)
        self.reset()

    def reset(self):
        self.active = False
        self.tags = []        # tags collected from matched recipients
        self.subject = None
        self.headers = []
        self.header_overflow = False

    def connect(self, hostname, family, hostaddr):
        """Accept the SMTP connection (no action needed)."""
        return CONTINUE

    def envfrom(self, f, *rest):
        """Arm tagging only for inbound mail, not for the user's own submits."""
        try:
            auth = self.getsymval("{auth_authen}") or ""
            self.reset()
            self.active = not bool(auth)
        except Exception:
            self.active = False
        return CONTINUE

    def envrcpt(self, to, *rest):
        """Collect tags for recipients whose local-part is in the services map."""
        if not self.active or not to:
            return CONTINUE
        try:
            if len(self.tags) >= 16:
                return CONTINUE
            # `to` may be a plain address or <...>-wrapped; take the local part.
            addr = to.strip()
            if addr.startswith("<") and addr.endswith(">"):
                addr = addr[1:-1]
            local, _, _domain = addr.rpartition("@")
            tag = SERVICES.get(local.lower())
            if tag and tag not in self.tags:
                self.tags.append(tag)
        except Exception:
            pass
        return CONTINUE

    def header(self, field, value):
        """Collect headers; remember the Subject header."""
        if not self.active:
            return CONTINUE
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
            if name == "subject" and self.subject is None:
                self.subject = value
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
        """Prepend [<tag>] to the Subject of unsigned inbound mail for matched recipients."""
        try:
            return self._eom()
        except Exception:
            # Fail open: a bug must never hold or refuse mail.
            _emit("error", "unexpected error; mail left untouched")
            return CONTINUE

    def _eom(self):
        if not self.active:
            return CONTINUE
        if not self.tags:
            return CONTINUE
        if self.header_overflow:
            _emit("skipped", "too many headers")
            return CONTINUE
        # Never tag a message that claims a content signature.
        if is_signed_or_encrypted(self.headers):
            _emit("skipped", "content-signed or encrypted (S/MIME or PGP)")
            return CONTINUE

        tag = self.tags[0]
        current = self.subject or ""
        if _has_tag_prefix(current, tag):
            _emit("skipped", "already tagged [%s]" % tag)
            return CONTINUE
        new_subject = _tagged_subject(current, tag)
        try:
            self.chgheader("Subject", 0, new_subject)
            _emit("added tag [%s]" % tag, "subject %r -> %r" % (_log_safe(current, 120), _log_safe(new_subject, 120)))
        except Exception:
            _emit("error", "failed to tag subject; left untouched")
        return CONTINUE


# -- registration -----------------------------------------------------------

Milter.factory = ServiceTagMilter
# pymilter answers a callback exception with TEMPFAIL by default, which makes
# Postfix hold or refuse the mail.  This milter must fail open instead.
Milter.set_exception_policy(CONTINUE)

if __name__ == "__main__":
    runmilter("mail-service-tag", SOCKET)
