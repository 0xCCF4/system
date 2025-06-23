{ ... }: {
  imports = [
    ../external/private/users/mx.nix
  ];

  config = {
    users.users.mx =
      {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        createHome = true;
        homeMode = "700";
        uid = 1000;
      };
  };
}
