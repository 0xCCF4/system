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
      ports = [ 22 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };

    mine.persistence.enable = true;

    # Remote unlock luks via ssh+tor
    mine.boot.remoteUnlock = true;
    mine.boot.tor.enable = true;
    mine.boot.remoteUnlockTorOnly = false;

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

    # no resolver on the host: eternis resolves like the other hosts (resolved ->
    # dnscrypt-proxy, local only), the microVMs through their own resolver microVM (dns.nix);
    # for a DNS server of the home LAN later: mine.services.unbound.lanInterfaces
    mine.services.unbound.enable = false;

    # peers on cloud-admin reach the microVMs on their ULA through eternis
    mine.guestUla.advertiseOn = [ "cloud-admin" ];
    # networkd only accepts RAs without IPv6 forwarding by default, the microVMs enable it
    systemd.network.networks."10-lan".networkConfig.IPv6AcceptRA = true;

    # headless server on systemd-networkd: no NetworkManager (nor its ModemManager,
    # wpa_supplicant) from the hardware profile
    networking.networkmanager.enable = false;
    # ... and no dhcpcd next to systemd-networkd, which alone configures the LAN (10-lan:
    # static address, IPv6 by RA) and the microVM taps; dhcpcd also took a DHCP lease on lanLeft
    networking.useDHCP = false;

    # the home LAN is trusted for SSH and mosh (besides cloud-admin)
    mine.ssh.trustedInterfaces = [ "lanLeft" ];
  };
}
