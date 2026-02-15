{ pkgs
, lib
, config
, ...
}:
with lib;
{
  options.mine.printing =
    let
      presets = config.mine.presets;
    in
    with types;
    mkOption {
      type = bool;
      default = presets.isWorkstation;
      description = "Enable printing support and install some common drivers for printers I use.";
    };

  config =
    let
      printing = config.mine.printing;
    in
    mkIf printing {
      services.printing.enable = true;
      services.printing.drivers = [ pkgs.gutenprint pkgs.hplip ];
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };
    };
}
