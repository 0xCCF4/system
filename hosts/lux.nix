{ lib, mine, ... }: with lib; {
  imports = [
    ../hardware/netcup.nix

    # Users
    ../users/mx.nix
  ] ++ mine.lib.optionalsIfExist [
    ../external/private/hosts/lux.nix
  ];

  config = {
    networking.hostName = "lux";
    mine.presets.primary = "server";

    services.openssh = {
      enable = true;
      ports = [ 5555 22 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        GatewayPorts = "yes";
      };
    };

    users.users.mx.openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCUipG3TQ0+yD3Nzi09x6UVQnZXlvnUkCJ4GJbfuAYqSR2pgY1jd3GtOjJHtcWC62Ydh+Z4Sus6dHTjsvDMcl8c7HNR5un0JpBpjFqZz8RLZZjYWEFvU7fU7IwZGMMOsIdje8fRgjlq96oQ8tSK3ljH6QA5/tJnPbhEy77l07juS4cY1U4X3CuQ+ULwnbpZ0TthRS9UzQHMVH+aJrY+aVMxKQ43cRzaVYCBbfriT2mlI5YvT+r1nL3sE3WXVIsagY0u9C40ASklXt/wR6b/MCMgIFruETFoIVJAnWIm0lwPQxdvCIyQLu5vjdg4Y+Tf15ZjAiD8/cxrQNxtfixPSjMp7I9Ji70EC2rDbbcZoL/mtVsec4Kp9KmZWovLnEt9GNjrnP3tZ4gnbPoxqEXNDowZ1zQkfhvp0mJNC8P504A2MR+1rC+f1gxMYg/ki1Xeyi5m5QLfOA7b7mwyzg58BqMSSBokK41ICAe+gDqBiWAP6rt/GzhavZ9xeyLRWwHhF/ZTsK2ZpYGHK18VpwG8pSpBjkZxxkeAzSFBP9lJcLK9PDhHpp6YsfE60uuA6bqanSh5HQz5UELuG14Tr5XBnY0qD8aGL73H+xMUUtDNCY48YgvIR8Tu+SzroTu5+ZlG/9CbXj0THkqqW9AAzn+lb7GVpDIWQEmGa8VE1FTLaIRd3w== mx laptop qubes vault - netcup"
    ];

    security.sudo.wheelNeedsPassword = false;

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    boot.kernelModules = [ "veth" "kvm" ];

    networking.useNetworkd = true;

    virtualisation.vmVariant = {
      # following configuration is added only when building VM with build-vm
      virtualisation = {
        memorySize = 4096;
        cores = 8;
      };
      users.users.mx.hashedPasswordFile = mkForce null;
      users.users.mx.password = "mx";
    };
  };
}
