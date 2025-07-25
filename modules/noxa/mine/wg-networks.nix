{ ... }: {
  # Policy: Only me has access to this network
  # Use-case: Me connecting to the SSH of the server
  # Allowed services: SSH maintenance port
  wireguard.cloud-maintenance = {
    networkAddress = "10.1.1.0/24";
    members = {
      lux.deviceAddresses = "10.1.1.0/32"; # cloud (server)
      lux.advertise.server.listenPort = 51820;

      ignis.deviceAddresses = "10.1.1.1/32"; # my laptop
    };
  };

  # Policy: Many have access to this network
  # Use-case: Someone uses the VPN to connect to the Internet
  # Allowed services: NAT to the Internet
  wireguard.cloud-vpn = {
    networkAddress = "10.1.2.0/24";
    members = {
      lux.deviceAddresses = "10.1.2.0/32"; # cloud (server)
      lux.advertise.server.listenPort = 51821;

      ignis.deviceAddresses = "10.1.2.1/32"; # my laptop
      ignis.backend = "wg-quick";
      ignis.autostart = false;
    };
  };

  # Policy: Many have access to this network
  # Use-case: Someone using services hosted in the cloud
  # Allowed services: Matrix, mail IMAP, ...
  wireguard.cloud-shared = {
    networkAddress = "10.1.3.0/24";
    members = {
      lux.deviceAddresses = "10.1.3.0/32"; # cloud (server)
      lux.advertise.server.listenPort = 51822;

      ignis.deviceAddresses = "10.1.3.1/32"; # my laptop
    };
  };

  #  # Policy: The different locations connect via this network 
  #  # Use-case: Port forwarding services to the Internet
  #  # Allowed services: Minecraft server hosted at home, forwarding to the Internet
  #  wireguard.cloud-expose = {
  #    networkAddress = "10.1.3.0/24";
  #    members = {
  #      lux.deviceAddresses = "10.1.2.0/32"; # cloud (server)
  #      lux.advertise.server.listenPort = 51823;
  #
  #      eternis.deviceAddresses = "10.1.2.1/32"; # home cluster
  #    };
  #  };
  #
  #  # Policy: Only me has access to this network
  #  # Use-case: I want to access my home network from the outside
  #  # Allowed services: SSH maintenance ports
  #  wireguard.home-internal = {
  #    networkAddress = "10.2.1.0/24";
  #    nestingLevel = 1;
  #    members = {
  #        eternis.deviceAddresses = "10.2.1.0/32"; # home cluster (server)
  #        eternis.advertise.server.listenPort = 51820;
  #
  #        ignis.deviceAddresses = "10.2.1.1/32"; # my laptop
  #    };
  #  };
  #
  #  # Policy: Access to others is granted
  #  # Use-case: Someone uses the services hosted at home
  #  # Allowed services: Services hosted at home like Nextcloud
  #  wireguard.home-shared = {
  #    networkAddress = "10.2.2.0/24";
  #    members = {
  #        eternis.deviceAddresses = "10.2.1.0/32";
  #        eternis.advertise.server.listenPort = 51821;
  #
  #        ignis.deviceAddresses = "10.2.1.1/32"; # my laptop
  #    };
  #  };
}
