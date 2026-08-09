{ self, inputs, lib, ... }: with lib; let
  installerHosts = [ "lux" "ignis" "solis" "eternis" ];

  mkInstallerIso = host:
    (self.noxaConfiguration.extendModules {
      modules = [{
        nodes.${host}.configuration = {
          imports = [ inputs.nixos-generators.nixosModules.install-iso ];

          system.stateVersion = mkForce "25.11";

          mine.boot.remoteUnlock = mkForce false;
          mine.boot.tor.enable = mkForce false;
        };
      }];
    }).config.nodes.${host}.configuration.system.build.isoImage;
in
{
  perSystem = { system, ... }: {
    packages = listToAttrs (map
      (host: nameValuePair "${host}-installer-iso" (mkInstallerIso host))
      installerHosts);
  };
}
