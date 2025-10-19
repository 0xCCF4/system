{ config, lib, ... }: with lib; with builtins; {
  options.mine.luksRemoteUnlock = with types; {
    enable = mkOption {
      type = bool;
      default = false;
      description = ''
        Enable remote unlocking of LUKS devices via SSH.
      '';
    };
  };

  config =
    let
      cfg = config.mine.luksRemoteUnlock;
    in
    mkIf cfg.enable {
      boot.kernelParams = [ "ip=dhcp" ];
      boot.initrd = {
        # todo
        #  availableKernelModules = [ "r8169" ];
        #  network = {
        #    enable = true;
        #    ssh = {
        #      enable = true;
        #      port = 4444;
        #      authorizedKeys = [ "ssh-rsa AAAAyourpublic-key-here..." ];
        #      hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
        #      shell = "/bin/cryptsetup-askpass";
        #    };
        #  };
      };
    };
}
