{ config
, pkgs
, lib
, ...
}:
with lib;
{
  config = {
    services.fail2ban = {
      enable = mkDefault config.services.sshd.enable;
      bantime-increment = {
        # https://nixos.wiki/wiki/Fail2ban
        enable = true;
        formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
        maxtime = "168h"; # Do not ban for more than 1 week
        overalljails = true; # Calculate the bantime based on all the violations
      };

      ignoreIP = [
        "10.0.0.0/8"
        "192.0.0.0/8"
      ];
    };
  };
}
