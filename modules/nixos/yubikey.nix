{ pkgs
, lib
, config
, ...
}:
with lib; with builtins;
{
  imports = [
    ./presets.nix
  ];

  options.mine.yubikey.enable = with types;
    let
      presets = config.mine.presets;
    in
    mkOption {
      type = bool;
      default = presets.isWorkstation;
      description = "Install driver and services for YubiKey devices";
    };

  config = mkIf config.mine.yubikey.enable {
    services.udev.packages = [ pkgs.yubikey-personalization ];

    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    security.pam.services = {
      login.u2fAuth = true;
      sudo.u2fAuth = true;
    };

    services.pcscd.enable = true;
  };
}
