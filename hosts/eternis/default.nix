{ lib
, self
, microvm
, noxa
, ...
}:
with lib;
let
  siblingModules = noxa.lib.nixDirectoryToAttr' ./.;
in
{
  imports = attrValues siblingModules
    ++ [
    ../../hardware/minisforumMS1.nix

    microvm.nixosModules.host
  ]
    ++ self.lib.optionalsIfExist [
    ../../external/private/hosts/eternis.nix
  ];

  config = {
    # General settings
    networking.hostName = "eternis";
    mine.presets.primary = "server";
    networking.hostId = "806204b5";

    mine.admins = [ "mx" ];

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # SSH
    services.openssh = {
      enable = true;
      ports = [
        5555
        22
      ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    mine.persistence.enable = true;

    # Remote unlock luks via ssh+tor
    mine.boot.remoteUnlock = true;
    mine.boot.tor.enable = true;

    # back up to ourselves: pool -> tank, over ssh to localhost
    mine.zrb.backupNode = "eternis";
    mine.zrb.backupSSH = "localhost";
    services.zrb.client.user = "zrbclient";
    services.zrb.client.group = "zrbclient";
    services.zrb.server.primary.enable = true;

    #mine.vm.networks = {
    #  vm-test.members = [ "green" "red" "<internet>" ];
    #  abc.members = [ "red" "<host>" ];
    #};

    #microvm = {
    #autostart = [ "log" ];
    #vms.prometheus = {
    #  restartIfChanged = true;
    #  config = {
    #    #imports = [../hardware/microvm.nix];
    #
    #
    #  };
    #};
    #};

    services.resolved.enable = false;
    mine.services.unbound.enable = true;

    # peers on cloud-admin reach the microVMs on their ULA through eternis
    mine.guestUla.advertiseOn = [ "cloud-admin" ];
    # networkd only accepts RAs without IPv6 forwarding by default, the microVMs enable it
    systemd.network.networks."10-lan".networkConfig.IPv6AcceptRA = true;
  };
}
