{ lib, ... }:
with lib;
{
  # Not `self.lib.optionalsIfExist`: this is used inside `imports`, so it may only
  # depend on special args, which are provided by the consuming flake
  imports = filter builtins.pathExists [
    ../external/private/home
  ];
}
