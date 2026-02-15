{ lib
, config
, ...
}:
with lib;
{
  options.mine.presets = with types;
    let
      cfg = config.mine.presets;
    in
    {
      primary = mkOption {
        type = enum [
          "workstation"
          "server"
        ];
        default = "server";
        description = "Primary usage of the system. This is used to determine various default settings.";
      };
      isServer = mkOption {
        type = bool;
        default = cfg.primary == "server";
        readOnly = true;
        description = "True if the system's primary usage is being a server.";
      };
      isWorkstation = mkOption {
        type = bool;
        default = cfg.primary == "workstation";
        readOnly = true;
        description = "True if the system's primary usage is being a workstation.";
      };
    };
}
