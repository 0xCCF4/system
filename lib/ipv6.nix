{ lib, netLib }: with lib; with builtins; {
  # Deterministic, salted, hash-derived IPv6 address for `name` inside
  # `network` (a "prefix/64" string).
  hashedIpv6Address = { salt, network, name }:
    let
      hashMarker = 1 * (netLib.pow 2 60); # fixed top-nibble marker
      # 15 hex chars = 60 bits + 0x01 prefix
      hashBits = fromHexString (substring 0 15 (hashString "sha256" (salt + name)));
    in
    (netLib.decompose (netLib.assignAddress network (hashMarker + hashBits))).addressNoMask;
}
