{ config, self, noxa, lib, ... }: {
  config._module.args = {
    luxAddr6For = network: name:
      self.lib.hashedIpv6Address {
        salt = config.mine.info.ipv6Salt;
        inherit network name;
      };

    luxPublicNetwork6 = (noxa.lib.net.decompose "${config.mine.info.public.ipv6}/64").networkNoMask + "/64";
  };
}
