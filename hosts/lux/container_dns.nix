# DNS of the containers: they are IPv6 only, so an IPv4-only name needs a synthesized
# 64:ff9b::/96 address (DNS64) to be reached through the NAT64. An unbound on lux answers
# them on their veth host addresses, adds DNS64, and forwards everything else to resolved's
# stub (and so to dnscrypt-proxy with its cloaking, /etc/hosts, ...), as the containers got
# it before from resolved directly. lux itself keeps resolved and native IPv4.
#
# DNS64 only synthesizes for names without AAAA. Whether a container may actually use the
# NAT64 is decided by mine.nat64.clients and the forward chain (hosts/lux/firewall.nix);
# the others fail on IPv4-only names as before. The mailserver keeps its own unbound.
{ config
, lib
, luxPublicNetwork6
, ...
}:
with lib;
let
  containers = attrValues config.containers;
in
{
  services.unbound = {
    enable = true;
    resolveLocalQueries = false; # lux itself keeps resolved
    enableRootTrustAnchor = false; # no validation here (dns64 iterator), Quad9 validates upstream
    settings = {
      server = {
        interface = map (container: container.hostAddress6) containers;
        # the veth addresses exist only while their container runs
        ip-freebind = true;
        # the containers' own addresses (public and guest ULA), the source of their queries
        access-control = map (container: "${container.localAddress6}/128 allow") containers
          ++ map (address: "${address}/128 allow") (attrValues config.mine.guestUla.addresses);
        module-config = ''"dns64 iterator"'';
        dns64-prefix = config.mine.nat64.prefix;
        # the upstream is resolved's stub on 127.0.0.53
        do-not-query-localhost = false;
        hide-identity = true;
        hide-version = true;
        deny-any = true; # no ANY answers (mostly used for amplification)
        # DNS rebinding: an external name (e.g. a feed miniflux fetches) cannot point a
        # container at loopback, the veth host addresses, the ULAs or lux' own addresses;
        # the own names (cloaked ULA answers, public records) are exempt
        private-address = config.mine.services.unbound.privateAddresses ++ [ luxPublicNetwork6 ];
        private-domain = [ "${config.mine.info.domain}." "vlan." "lan." ];
      };
      forward-zone = [
        {
          name = ".";
          forward-addr = [ "127.0.0.53" ];
        }
      ];
    };
  };
}
