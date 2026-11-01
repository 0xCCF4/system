{ pkgs
, lib
, config
, ...
}:
with lib;
{
  options.mine.printing =
    with types;
    mkOption {
      type = bool;
      # off for now: back with statically configured printers (no discovery, see below)
      default = false;
      description = ''
        Enable printing support and install some common drivers for printers I use.
      '';
    };

  config =
    let
      printing = config.mine.printing;
    in
    mkIf printing {
      services.printing.enable = true;
      services.printing.drivers = [
        pkgs.gutenprint
        pkgs.hplip
      ];
      services.printing.browsed.enable = false;
    };
}
