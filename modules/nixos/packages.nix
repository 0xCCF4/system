{ pkgs, ... }: {
  # Add some default packages to the system.
  environment.systemPackages = with pkgs; [
    nano
    git
    openssh
    openssl
    coreutils
    nftables
  ];
}
