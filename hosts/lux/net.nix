{ config
, self
, noxa
, lib
, ...
}:
{
  # peers on cloud-admin reach the containers with a ULA (mine.guestUla) through lux
  config.mine.guestUla.advertiseOn = [ "cloud-admin" ];

  config._module.args = {
    luxAddr6For =
      network: name:
      noxa.lib.net.hashedAddress {
        salt = self.lib.requireOption "mine.info.ipv6Salt" config.mine.info.ipv6Salt;
        inherit network name;
      };

    luxPublicNetwork6 =
      (noxa.lib.net.decompose "${self.lib.requireOption "mine.info.public.ipv6" config.mine.info.public.ipv6}/64").networkNoMask + "/64";
  };
}
