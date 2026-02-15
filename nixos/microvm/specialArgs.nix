{ config, options, specialArgs, lib, ... }: with lib; {
  config = ({ } // (
    if options ? "microvm" then
      {
        microvm.vms = mkMerge (map
          (vmName: {
            "${vmName}" = {
              inherit specialArgs;
              config._module.args = {
                hostConfig = config;
                inherit vmName;
              };
            };
          })
          (attrNames config.microvm.vms));
      }
    else
      { }
  )
  );
}
