{ noxa, lib, mine, ... }: {
  imports = noxa.lib.nixDirectoryToList ./. ++
    mine.lib.optionalIfExist ../../external/private/modules/home;
}
