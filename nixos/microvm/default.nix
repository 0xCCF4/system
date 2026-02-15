{ noxa, pkgs, microvm, ... }: {
  imports = noxa.lib.nixDirectoryToList ./.;
}
