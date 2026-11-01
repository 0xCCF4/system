{ config
, lib
, options
, ...
}:
with lib;
let
  # stable per name (0-2 are reserved, CIDs are host-wide)
  cid = name: 1000 + fromHexString (substring 0 7 (builtins.hashString "sha256" "microvm-vsock-cid:${name}"));

  admins = map (name: config.users.users.${name}) config.mine.admins;
in
{
  # Root shell in every microVM (mine.microvm.names) from the host only, over vsock instead
  # of the network:
  #   microvm -s <name>            (as root on the VM, with your keys, e.g. `ssh -A` to the host)
  #   ssh root@vsock/<cid>         (cid: /var/lib/microvms/<name>/current/share/microvm/vsock-cid)
  # sshd in the microVM listens on vsock only (systemd-ssh-generator), not on its network.
  config = optionalAttrs (options ? microvm) {
    microvm.vms = genAttrs config.mine.microvm.names (name: {
      config = {
        microvm.vsock.cid = cid name;
        microvm.vsock.ssh.enable = true;

        services.openssh = {
          openFirewall = false;
          # (the vsock connections are inetd style `sshd -i`, independent of these)
          listenAddresses = [{ addr = "127.0.0.1"; port = 22; }];
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
          };
        };
        users.users.root.openssh.authorizedKeys = {
          keys = concatMap (user: user.openssh.authorizedKeys.keys) admins;
          keyFiles = concatMap (user: user.openssh.authorizedKeys.keyFiles) admins;
        };
      };
    });

    assertions = [{
      assertion = allUnique (map cid config.mine.microvm.names);
      message = "mine.microvm: two microVMs got the same vsock CID, rename one";
    }];
  };
}
