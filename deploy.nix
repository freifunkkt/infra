{
  network.description = "ffkt network";

  falterturm = { config, pkgs, ... }:
    {
      deployment = {
        targetEnv = "none";
        targetHost = "gw01.freifunk-kitzingen.de";
      };

      require = [ ./hosts/falterturm.nix ];
    };

  #stachus = { ... }:
  #  {
  #    deployment = {
  #      targetEnv = "none";
  #      targetHost = "195.30.94.61";
  #    };

  #    require = [ ./hosts/stachus.nix ];
  #  };
}

