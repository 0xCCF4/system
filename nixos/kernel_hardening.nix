{ config
, lib
, ...
}:
with lib;
let
  cfg = config.mine.kernelHardening;
in
{
  options.mine.kernelHardening = with types; {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Network related kernel hardening (sysctls).";
    };

    strictArp = mkOption {
      type = bool;
      default = true;
      description = ''
        Answer ARP only for the addresses of the interface the request arrived on, and
        announce the outgoing interface's address (arp_ignore=1, arp_announce=2): the
        addresses of the other interfaces (e.g. the NAT64 link) stay internal. For hosts
        with several interfaces, breaks proxy ARP and addresses answered across interfaces.
      '';
    };

    bpfJitHarden = mkOption {
      type = bool;
      default = config.mine.presets.isServer;
      defaultText = literalExpression "config.mine.presets.isServer";
      description = "Constant blinding in JIT compiled BPF (bpf_jit_harden=2), against JIT spraying.";
    };
  };

  # (the conf.* patterns also cover the interfaces created later, the value of `all` alone
  # does not override an interface's own for these)
  config = mkIf cfg.enable {
    boot.kernel.sysctl = mapAttrs (_: mkDefault) ({
      # ICMP redirects let anyone on the link reroute the traffic, none of our networks
      # needs them
      "net.ipv4.conf.*.accept_redirects" = false;
      "net.ipv4.conf.*.secure_redirects" = false;
      "net.ipv6.conf.*.accept_redirects" = false;
      # the forwarding hosts are no gateway of a shared LAN, redirects only leak topology
      "net.ipv4.conf.*.send_redirects" = false;
      # TIME-WAIT assassination by forged RSTs (RFC 1337)
      "net.ipv4.tcp_rfc1337" = true;
      # log the martians the kernel drops itself (rate limited)
      "net.ipv4.conf.*.log_martians" = true;
    } // optionalAttrs cfg.strictArp {
      "net.ipv4.conf.all.arp_ignore" = 1;
      "net.ipv4.conf.all.arp_announce" = 2;
    } // optionalAttrs cfg.bpfJitHarden {
      "net.core.bpf_jit_harden" = 2;
    });
  };
}
