{ pkgs
, lib
, config
, ...
}:
with lib;
{
  imports = [
    ../persistence.nix
  ];

  options.mine.persistence =
    with types;
    {
      vmDirectories = mkOption {
        description = "List of directories to persist relative to the microvm host directory.";
        default = [ ];
      };
      vmFiles = mkOption {
        description = "List of files to persist relative to the microvm host directory.";
        default = [ ];
      };
    };

  config =
    let
      cfg = config.mine.persistence;
      microvm = mine.lib.evalMissingOption config "microvm" { vms = { }; };
    in
    mkIf ((options.microvm or null) != null)
      (
        {
          mine.persistence.directories = map (path: "${microvm.stateDir}/${path}") cfg.vmDirectories;
          mine.persistence.files = map (path: "${microvm.stateDir}/${path}") cfg.vmFiles;
        } else
      { })
  );
}
