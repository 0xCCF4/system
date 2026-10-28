{ lib, ... }:
with lib;
{
  imports = filter builtins.pathExists [
    ../external/private/noxa
  ];
}
