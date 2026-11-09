{ inputs, lib, self, ... }:
with lib;
let
  modules = inputs.noxa.lib.nixDirectoryToAttr' ./.;
  noDefault = filterAttrs (name: value: name != "default") modules;

  # Home modules refer to this flake as `mineSelf`, not via the `self` special arg:
  # when these modules are consumed by another flake, its `self` is a different flake.
  # The `key` deduplicates the module, so several hmModules can be imported at once.
  args = {
    key = "${toString ./.}#mineSelf";
    _module.args.mineSelf = self;
  };

  withArgs = module: { ... }: {
    imports = [ args module ];
  };
in
{
  flake = {
    hmModules = mapAttrs (name: withArgs) noDefault // {
      default = { ... }: {
        imports = [ args ] ++ attrValues noDefault;
      };
    };
  };
}
