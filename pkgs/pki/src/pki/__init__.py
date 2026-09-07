"""cfssl-backed internal PKI tooling.

Architecture: the root CA key lives fully offline (age-encrypted to an
operator identity, never resident on any running host, see root.py); the
intermediate CA key lives on lux but is only ever read by a short-lived,
admin-triggered CLI invocation (see admin.py), never by a long-running
network listener; the OCSP-responder key is a separate, scope-restricted
delegate key, safe to leave resident in an always-on process; leaf certs
are only ever signed via an explicit `pki admin batch` run, never
automatically or over the network.
"""

__version__ = "0.1.0"
