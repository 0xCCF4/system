{ inputs
, pkgs
, lib
, config
, options
, ...
}:
with lib;
{
  config = {
    services.orca.enable = false;
  };
}
