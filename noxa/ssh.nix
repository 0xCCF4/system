{ lib, config, ... }: with lib; with builtins;
{
  nodes =
    let
      from = [ "ignis" "solis" ];
      to = config.nodeNames;
    in
    mkMerge (map
      (from: ({
        "${from}".configuration.ssh.grants = mkMerge (map
          (to: {
            "${to}" = {
              from = "mx";
              to.node = to;
              to.user = "mx";
              options.pty = true;
              options.agentForwarding = true;
              options.allowPortForwarding = true;
              to.hostname = mkDefault "${to}.vlan";
            };
          })
          (filter (name: name != from) to));
      }))
      from);
}
