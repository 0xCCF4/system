{ lib
, config
, ...
}:
with lib;
let
  caddyPorts = [ 80 443 ];
in
{
  # NOTE: this only defines the `forward` hook (and the microVM chains of
  # nixos/microvm/networking.nix). Host-exposed services are filtered by the
  # standard networking.firewall module.
  config = {
    # (the ULA guard covers mine.wanInterfaces, both LAN ports: lanLeft and lanRight)

    # the microVMs are IPv6 only and reachable only on their ULA (a NAT64 comes up with
    # the first <internet> network, masqueraded to mine.wanInterfaces)
    networking.nftables.tables.eternis-forward-traffic = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority filter; policy drop;

          # drop invalid, and forward established connections
          ct state invalid drop
          ct state established,related accept

          # wireguard -> caddy, only over IPv6 (its ULA)
          iifname == "cloud-admin" oifname == "${config.mine.vm.guests.caddy.tap}" meta nfproto ipv6 tcp dport { ${concatMapStringsSep ", " toString caddyPorts} } accept

          # microVM <-> microVM (mine.vm.networks), e.g. caddy -> paperless
          ${config.mine.vm.forwardRules}

          # the NAT64 of the <internet> microVMs (nixos/nat64.nix), empty without one
          ${config.mine.nat64.forwardRules}

          drop
        }
      '';
    };
  };
}
