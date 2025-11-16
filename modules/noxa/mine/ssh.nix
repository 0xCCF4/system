{ lib, config, ... }: with lib; with builtins;
{
  ssh.grants = [ ]
    ++
    # From ignis to all other nodes
    (map
      (to: ({
        from.node = "ignis";
        from.user = "mx";
        to.node = to;
        to.user = "mx";
      }))
      (filter (name: name != "ignis") config.nodeNames))
    ++
    # From solis to all other nodes
    (map
      (to: ({
        from.node = "solis";
        from.user = "mx";
        to.node = to;
        to.user = "mx";
      }))
      (filter (name: name != "solis") config.nodeNames));
}
