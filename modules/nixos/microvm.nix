{ config, options, specialArgs, lib, ... }: with lib; {
  xx;;;;;
  config = trace (options ? "microvm") ({ } // (
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
