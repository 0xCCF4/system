{ config
, self
, noxa
, lib
, ...
}:
{
  config._module.args = {
    luxAddr6For =
      network: name:
      self.lib.hashedIpv6Address {
        salt = self.lib.requireOption "mine.info.ipv6Salt" config.mine.info.ipv6Salt;
        inherit network name;
      };

    luxPublicNetwork6 =
      (noxa.lib.net.decompose "${self.lib.requireOption "mine.info.public.ipv6" config.mine.info.public.ipv6}/64").networkNoMask + "/64";
  };
}
