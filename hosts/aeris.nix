{ lib
, self
, ...
}:
with lib;
{
  imports = [
    ../hardware/dellOptiplex3050Micro.nix
  ]
  ++ self.lib.optionalsIfExist [
    ../external/private/hosts/aeris.nix
  ];

  config = {
    networking.hostName = "aeris";
    mine.presets.primary = "server";
    networking.hostId = "087287a5";

    mine.admins = [ "mx" ];

    # SSH
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
      };
    };
  };
}
