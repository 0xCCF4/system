# pki/

| Command | Does |
|---|---|
| `pki init` | bootstrap the CA (once) |
| `pki issue-ocsp` | issue/renew the OCSP responder cert; writes its agenix secret directly |
| `pki issue <name> --cn ... [--san ...]` | issue/renew a leaf cert |
| `pki revoke <name> [--reason ...]` | mark revoked in the ledger |
| `pki gencrl` | regenerate the CRL |
| `pki status` | list certs + days-to-expiry |
| `pki sync-db` | rebuild the sqlite DB lux needs (Nix calls this, you don't) |
