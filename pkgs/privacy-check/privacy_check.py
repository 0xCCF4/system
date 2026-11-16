#!/usr/bin/env python3
"""Check the public repo for private data before it is committed.

Scans every file in the git index (the staged state, what the commit will contain),
except submodules (external/private is a separate, private repo):

1. Deny list: the private values listed in external/private/privacy-denylist.txt
   (domain, IPs, providers, MACs, keys, ...). Any match fails. The list itself is
   private, so the check needs the submodule; without it, it fails.
2. Heuristics, for values not on the deny list yet: globally routable IPv4/IPv6
   addresses, email addresses and MAC addresses fail too, unless they are listed in
   pkgs/privacy-check/allowlist.txt (public, for well-known third-party values).

Usage: privacy_check.py [--worktree]   (default: the index; --worktree: tracked files
as they are on disk). Exit code 1 on findings. Bypass for one commit: --no-verify.
"""

import ipaddress
import os
import re
import subprocess
import sys

DENYLIST = "external/private/privacy-denylist.txt"
ALLOWLIST = "pkgs/privacy-check/allowlist.txt"

IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.]*\d)")
# candidates with at least two colons, validated by ipaddress afterwards
IPV6 = re.compile(r"(?<![\w:.])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?![\w:])")
EMAIL = re.compile(r"(?<![\w.+-])[\w.+-]+@([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)")
MAC = re.compile(r"(?<![\w:])(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}(?![\w:])")
# systemd unit instances look like addresses (foo@bar.service)
NOT_EMAIL_SUFFIXES = (".service", ".target", ".socket", ".mount", ".timer", ".slice",
                      ".path", ".device", ".scope", ".swap", ".automount")


def git(*args, input=None):
    return subprocess.run(["git", *args], input=input, capture_output=True, check=True).stdout


def read_list(path):
    entries = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                entries.append(line)
    return entries


def files(worktree):
    """(path, content bytes) of every tracked file, submodules (mode 160000) skipped."""
    entries = []
    for record in git("ls-files", "--stage", "-z").split(b"\0"):
        if not record:
            continue
        meta, path = record.split(b"\t", 1)
        mode, obj, _stage = meta.split(b" ")
        if mode == b"160000":
            continue
        entries.append((path.decode(), obj.decode()))
    if worktree:
        for path, _ in entries:
            if os.path.isfile(path):
                with open(path, "rb") as handle:
                    yield path, handle.read()
        return
    if not entries:
        return
    # one batch read of the staged blobs
    out = git("cat-file", "--batch", input="".join(obj + "\n" for _, obj in entries).encode())
    pos = 0
    for path, _ in entries:
        header_end = out.index(b"\n", pos)
        size = int(out[pos:header_end].split(b" ")[2])
        start = header_end + 1
        yield path, out[start:start + size]
        pos = start + size + 1


def word_pattern(value):
    # a whole word: not preceded or followed by a letter, digit or underscore
    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(value) + r"(?![A-Za-z0-9_])", re.IGNORECASE)


# global in ipaddress' eyes, but no one's address: NAT64 prefixes, the IPv6 documentation
# prefix of RFC 9637, deprecated site-local, the old IPv4-compatible range (also catches
# fragments like the "::53" of "<network>::53")
NOT_ADDRESSES = [ipaddress.ip_network(net) for net in
                 ("64:ff9b::/96", "64:ff9b:1::/48", "3fff::/20", "fec0::/10", "::/8")]
# reserved example domains (RFC 2606/6761)
EXAMPLE_DOMAINS = re.compile(r"(^|\.)(example\.(com|net|org)|example|invalid|test|localhost)$")


def is_public_ip(text):
    try:
        address = ipaddress.ip_address(text)
    except ValueError:
        return False
    if address.version == 6 and address.ipv4_mapped:
        return False
    if address.is_multicast or any(address in net for net in NOT_ADDRESSES if net.version == address.version):
        return False
    # netmasks like ffff:ffff:ffff:ff00:: are no addresses either
    if address.version == 6 and str(address).startswith("ffff:"):
        return False
    return address.is_global


def main():
    worktree = "--worktree" in sys.argv[1:]
    os.chdir(git("rev-parse", "--show-toplevel").decode().strip())

    if not os.path.isfile(DENYLIST):
        print(f"privacy-check: {DENYLIST} is missing (the private submodule is not checked "
              "out), cannot check for private data. Check out external/private, or commit "
              "with --no-verify if you are sure.", file=sys.stderr)
        return 1
    deny = [(value, word_pattern(value)) for value in read_list(DENYLIST)]
    allow = {value.lower() for value in read_list(ALLOWLIST)} if os.path.isfile(ALLOWLIST) else set()

    findings = []
    for path, data in files(worktree):
        if b"\0" in data[:8192]:
            continue  # binary
        text = data.decode("utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            for value, pattern in deny:
                if pattern.search(line):
                    findings.append((path, lineno, "private value from the deny list", value))
            for match in IPV4.finditer(line):
                value = match.group(0)
                if is_public_ip(value) and value.lower() not in allow:
                    findings.append((path, lineno, "public IPv4 address", value))
            for match in IPV6.finditer(line):
                value = match.group(0)
                if is_public_ip(value) and value.lower() not in allow:
                    findings.append((path, lineno, "public IPv6 address", value))
            for match in EMAIL.finditer(line):
                value, domain = match.group(0), match.group(1).lower()
                if domain.endswith(NOT_EMAIL_SUFFIXES) or domain.split(".")[-1] in ("nix", "py", "lua", "sh"):
                    continue
                if EXAMPLE_DOMAINS.search(domain):
                    continue
                if value.lower() not in allow and "@" + domain not in allow:
                    findings.append((path, lineno, "email address", value))
            for match in MAC.finditer(line):
                value = match.group(0)
                if value.lower() not in allow:
                    findings.append((path, lineno, "MAC address", value))

    if not findings:
        return 0
    print("privacy-check: possible private data in the public repo:", file=sys.stderr)
    for path, lineno, kind, value in findings:
        print(f"  {path}:{lineno}: {kind}: {value}", file=sys.stderr)
    print("Move the values into external/private (see external/private/privacy-denylist.txt).\n"
          f"Well-known third-party values that may stay public go into {ALLOWLIST}.\n"
          "Bypass for one commit: git commit --no-verify", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
