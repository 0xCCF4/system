{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.mine.kernelHardening;

  # per network namespace: also set inside the containers with a private network (below)
  # (the conf.* patterns also cover the interfaces created later, the value of `all` alone
  # does not override an interface's own for these)
  networkSysctls = mapAttrs (_: mkDefault) ({
    "net.ipv4.conf.*.accept_redirects" = false; # ICMP redirects let anyone on the link reroute traffic, none of our networks needs them
    "net.ipv4.conf.*.secure_redirects" = false; # same, for redirects from the gateway
    "net.ipv6.conf.*.accept_redirects" = false; # same, IPv6
    "net.ipv4.conf.*.send_redirects" = false; # the forwarding hosts are no gateway of a shared LAN, redirects only leak topology
    "net.ipv4.tcp_rfc1337" = true; # no TIME-WAIT assassination by forged RSTs (RFC 1337)
    "net.ipv4.conf.*.log_martians" = true; # log the martians the kernel drops itself (rate limited)
    "net.ipv4.icmp_echo_ignore_all" = 1; # no answer to IPv4 pings (IPv6 unaffected): use TCP checks (e.g. zrb's route choice in nixos/zrb.nix)
  } // optionalAttrs cfg.strictArp {
    "net.ipv4.conf.all.arp_ignore" = 1; # answer ARP only for the addresses of the receiving interface
    "net.ipv4.conf.all.arp_announce" = 2; # announce the outgoing interface's own address
  });
in
{
  options.mine.kernelHardening = with types; {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Kernel hardening (sysctls).";
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

  # the containers with a private network get the network sysctls of their host (the others
  # are kernel-wide and apply to them anyway, they cannot set them)
  options.containers = mkOption {
    type = types.attrsOf (types.submodule ({ config, ... }: {
      config.config.boot.kernel.sysctl = mkIf (cfg.enable && config.privateNetwork) networkSysctls;
    }));
  };

  config = mkIf cfg.enable {
    boot.kernel.sysctl = networkSysctls // mapAttrs (_: mkDefault) ({
      "dev.tty.ldisc_autoload" = 0; # only CAP_SYS_MODULE may load TTY line discipline modules (n_hdlc, slcan, ...), N_TTY of terminals/serial ports unaffected
      "kernel.kexec_load_disabled" = 1; # no kexec until reboot (one-way): no runtime kernel swap by root, no kexec reboots or kdump
      "fs.protected_fifos" = 2; # no O_CREAT open of another user's FIFO in sticky dirs, also group-writable ones (systemd: 1, world-writable only)
      "fs.protected_regular" = 2; # same, for regular files (against files planted in /tmp before a privileged program writes)
      "vm.mmap_rnd_bits" = 32; # ASLR of 64-bit programs: 32 random bits, the x86-64 maximum (default 28)
    } // optionalAttrs config.mine.presets.isServer {
      "kernel.yama.ptrace_scope" = 2; # only root may ptrace (workstations keep 1: own children, for debugging), gdb/strace need sudo
      "fs.suid_dumpable" = 0; # no core dumps of setuid/privileged processes (systemd: 2)
      "vm.mmap_rnd_compat_bits" = 16; # ASLR of 32-bit programs: 16 bits (default 8); not on workstations, the gaps shrink the 4 GB of 32-bit Steam/Wine programs
    } // optionalAttrs config.mine.presets.isWorkstation {
      "kernel.sysrq" = 20; # only emergency sync (Alt+Druck+S) and the secure attention key (Alt+Druck+K, kills all on the console: at login screens only)
    } // optionalAttrs cfg.bpfJitHarden {
      "net.core.bpf_jit_harden" = 2; # constant blinding in JIT compiled BPF, against JIT spraying
    }) // {
      "kernel.kptr_restrict" = mkOverride 900 2; # kernel addresses read as 0 for everyone, root included (no KASLR leak); perf/bpftrace lose kernel symbols, `sysctl -w kernel.kptr_restrict=1` to profile (above NixOS' mkDefault 1)
    };

    boot.kernelParams = [
      "vsyscall=none" # no obsolete vsyscall page at a fixed address (default: execute-only emulation); only ~2012 static binaries need it
      "debugfs=off" # no /sys/kernel/debug (internal kernel state); powertop details and some driver debug files are gone, tracefs stays
      "random.trust_cpu=off" # RDRAND is mixed in but not counted as entropy (a weak/backdoored RDRAND cannot make early keys predictable)
      "random.trust_bootloader=off" # same, for the boot loader's seed; the jitter entropy makes the RNG ready within ~1s anyway
    ] ++ optionals config.mine.presets.isServer [
      "slab_nomerge" # separate slab caches per object type: a heap overflow cannot reach other types (some MB more memory)
      "init_on_free=1" # zero memory on free: no lingering secrets, use-after-free reads zeros (~1-5% in allocation-heavy loads)
      "page_alloc.shuffle=1" # randomized free page lists: less predictable heap layout (nearly free)
    ];

    # rarely used, historically buggy modules never load, not even by an explicit modprobe
    # (stronger than boot.blacklistedKernelModules, which only stops the autoload by alias);
    # kept on purpose: squashfs, erofs, udf, hfsplus, exfat, ntfs3 (ISOs, DVDs, Mac/Windows drives)
    boot.extraModprobeConfig = concatMapStrings (module: "install ${module} ${pkgs.coreutils}/bin/false\n") [
      "dccp" "sctp" "rds" "tipc" "n_hdlc" "ax25" "netrom" "x25" "rose" "decnet" "econet" # obscure network protocols, (remotely) auto-loadable
      "af_802154" "ipx" "appletalk" "psnap" "p8022" "p8023" "can" "atm" # same
      "adfs" "affs" "bfs" "befs" "cramfs" "efs" "freevxfs" "hpfs" "jffs2" "jfs" "minix" # rare filesystems, loaded by mounting a crafted image
      "nilfs2" "omfs" "qnx4" "qnx6" "sysv" "ufs" "hfs" "f2fs" # same
      "vivid" # video test driver, privilege escalations
    ];

    # servers: no core dumps on disk (they hold passwords, keys, decrypted data), crashes are
    # still logged in the journal; workstations keep them for coredumpctl debugging
    systemd.coredump.settings.Coredump.Storage = mkIf config.mine.presets.isServer (mkDefault "none");
  };
}
