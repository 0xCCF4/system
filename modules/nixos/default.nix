{ noxa, ... }: {
  imports = noxa.lib.nixDirectoryToList ./.;
}
