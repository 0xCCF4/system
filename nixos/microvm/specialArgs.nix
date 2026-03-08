{ config, options, specialArgs, lib, ... }: with lib; {
  options = with types; {
    mine.microvm.names = mkOption {
      type = listOf str;
      default = [ ];
      description = "List of microvm names to augment with specialArgs";
    };
  };
  config = ({ } // (
    if options ? "microvm" then
      {
        microvm.vms = mkMerge (map
          (vmName: {
            "${vmName}" = {
              inherit specialArgs;
              config._module.args = {
                inherit vmName;
                hostConfig = config;
              };
            };
          })
          (config.mine.microvm.names));
      }
    else
      { }
  )
  );
}
