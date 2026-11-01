{ lib
, pkgs
, ...
}:
with lib;
{
  config = {
    # Resolver of the other microVMs (mine.vm.dnsGuest), instead of an unbound on the host:
    # nothing on eternis' host answers DNS. Only reachable by the microVMs, not from the LAN,
    # the host or WireGuard (nixos/microvm/networking.nix).
    mine.microvm.names = [ "dns" ];
    microvm.vms.dns = {
      restartIfChanged = true;
      config = {
        microvm.mem = 512;
        imports = [
          ../../hardware/microvm.nix
          # the fleet's resolver setup: unbound (loopback, plus its ULA for the other
          # microVMs from nixos/microvm/networking.nix) forwarding to dnscrypt-proxy
          # (Quad9, blocklist), reached through the CLAT/NAT64
          ../../nixos/service_unbound.nix
          ../../nixos/dns.nix
        ];

        mine.services.unbound.enable = true;
        services.unbound.settings.server = {
          # validates itself (DNS64 first: it synthesizes from validated answers)
          module-config = mkForce ''"dns64 validator iterator"'';
          # internal names never leave (no cloaking rules here): answered locally (NXDOMAIN)
          local-zone = [ ''"vlan." static'' ''"lan." static'' ];
        };
        # IPv6 only behind the NAT64: only Quad9's IPv4 servers are reachable (CLAT)
        services.dnscrypt-proxy.settings.ipv6_servers = mkForce false;

        # to debug the resolver (microvm -s dns 'dig @::1 …')
        environment.systemPackages = [ pkgs.dig ];

        networking.firewall.allowedUDPPorts = [ 53 ];
        networking.firewall.allowedTCPPorts = [ 53 ];
      };
    };

    # IPv6 only (ULA), own tap interface, its upstream through the NAT64
    mine.vm.guests.dns = { };
    mine.vm.networks.dns.members = [ "dns" "<internet>" ];
    mine.vm.dnsGuest = "dns";
  };
}
