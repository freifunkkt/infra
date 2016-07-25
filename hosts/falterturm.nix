{ config, lib, pkgs, ... }:

let
  secrets = (import ../secrets);
in

{
  imports = [
    ../modules/default.nix
    ../modules/gateway.nix
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  ];
  
  hardware.enableAllFirmware = true;
  boot.initrd.availableKernelModules = [  "ata_piix" "virtio_pci" "virtio_blk" "xhci_pci" "ehci_pci" "ahci" "uhci_hcd" "usbhid" "usb_storage" "sd_mod" "sr_mod" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/aad7553d-c006-4f93-bca1-e5ef2c12404c";
      fsType = "ext4";
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/d015e204-43f6-4b51-a2b8-195933dabeda"; }
    ];
  
  nix = {
    binaryCachePublicKeys = [ "hydra.mayflower.de:9knPU2SJ2xyI0KTJjtUKOGUVdR2/3cOB4VNDQThcfaY= " ];
    binaryCaches = [ "https://hydra.mayflower.de/" ];
  };
  
  environment.systemPackages = with pkgs; [
    wget
    vim
    git
    traceroute
    htop
    atop
    tcpdump
  ];

  nix.maxJobs = 4;

  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;
  boot.loader.grub.device = "/dev/vda";

  freifunk.gateway = {
    enable = true;
    externalInterface = "enp0s3";
    ip4Interfaces = [ "tun0" "enp0s3" ];
    ip6Interface = "heipv6";
    ip6Tunnel = ''
      modprobe ipv6
      ip tunnel add heipv6 mode sit remote 216.66.86.114 local 188.68.56.228 ttl 255
      ip link set heipv6 up
      ip addr add 2001:470:6c:83::2/64 dev heipv6
      ip route add ::/0 dev heipv6
    '';
    
    #ist das die normale Konfiguration der Schnittstelle
    networkingLocalCommands = ''
      ip rule add from 188.68.56.228/32 lookup 5
      ip route replace default via 188.68.56.3 table 5
    '';
    
    graphite = secrets.stats.servername;
    segments = {
      ffkt = {
        baseMacAddress = "80:00:01:23:42";
        bridgeInterface = {
          ip4 = [ { address = "10.68.0.1"; prefixLength = 18; } ];
          ip6 = [
            { address = "fdef:ffc0:8fff::1"; prefixLength = 64; }
            { address = "2001:470:5035::1"; prefixLength = 64; }
          ];
        };
        dhcpRanges = [ "10.68.16.0,10.68.31.254,255.255.224.0,1h" ];
        ra.prefixes = [ "2001:470:5035::/64" "fdef:ffc0:8fff::/64" ];
        ra.rdnss = [ "2001:470:5035::1" "fdef:ffc0:8fff::1"];
        fastdConfigs = let
          secret = secrets.fastd.gw01.secret;
          #falterturm has no ipv6. Otherwise add external ipv6 in next line like "[2001:470:5035::1]"
          listenAddresses = [ "188.68.56.228"  "[2001:470:5035::1]" ];
        in {
          #preparation for inter-gateway-fastd-peering
          #backbone = {
          #  inherit secret listenAddresses;
          #  listenPort = 9999;
          #  mtu = 1426;
          #};
          mesh0 = {
            inherit secret listenAddresses;
            listenPort = 10000;
            mtu = 1280;
          };
          mesh1 = {
            inherit secret listenAddresses;
            listenPort = 10001;
            mtu = 1280;
          };
          #maybe more later
          #mesh2 = {
          #  inherit secret listenAddresses;
          #  listenPort = 10002;
          #  mtu = 1280;
          #};
          #mesh3 = {
          #  inherit secret listenAddresses;
          #  listenPort = 10003;
          #  mtu = 1280;
          #};
        };
        portBalancings = [
          { from = 10000; to = 10001; }
         # { from = 10001; to = 10002; }
         # { from = 10002; to = 10003; }
         # { from = 10003; to = 10000; }
        ];
      };
      #weiteres Segment...
      #welcome = {
      #  baseMacAddress = "80:ff:02:23:42";
      #  bridgeInterface = {
      #    ip4 = [ { address = "10.80.64.12"; prefixLength = 19; } ];
      #    ip6 = [
      #      { address = "fdef:ffc0:4fff:1::12"; prefixLength = 64; }
      #      { address = "2001:608:a01:3::12"; prefixLength = 64; }
      #    ];
      #  };
      #  dhcpRanges = [ "10.80.68.0,10.80.90.255,255.255.224.0,1h" ];
      #  ra.prefixes = [ "2001:608:a01:3::/64" ];
      #  ra.rdnss = [ "2001:608:a01:3::12" ];
      #  fastdConfigs = let
      #    secret = secrets.fastd.gwf02.secret;
      #    listenAddresses = [ "195.30.94.27" "[2001:608:a01::1]" ];
      #  in {
      #    mesh0 = {
      #      inherit secret listenAddresses;
      #      listenPort = 11000;
      #      mtu = 1426;
      #    };
      #    mesh1 = {
      #      inherit secret listenAddresses;
      #      listenPort = 11099;
      #      mtu = 1426;
      #    };
      #    mesh2 = {
      #      inherit secret listenAddresses;
      #      listenPort = 11001;
      #      mtu = 1280;
      #    };
      #    mesh3 = {
      #      inherit secret listenAddresses;
      #      listenPort = 11098;
      #      mtu = 1280;
      #    };
      #  };
      #  portBalancings = [
      #    { from = 11000; to = 11099; }
      #    { from = 11001; to = 11098; }
      #  ];
      #};
      #ein potenziell 3tes Segment
      #umland = {
      #  baseMacAddress = "80:01:02:23:42";
      #  bridgeInterface = {
      #    ip4 = [ { address = "10.80.96.12"; prefixLength = 19; } ];
      #    ip6 = [
      #      { address = "fdef:ffc0:4fff:2::12"; prefixLength = 64; }
      #      { address = "2001:608:a01:4::12"; prefixLength = 64; }
      #    ];
      #  };
      #  dhcpRanges = [ "10.80.98.0,10.80.111.255,255.255.224.0,1h" ];
      #  ra.prefixes = [ "2001:608:a01:4::/64" ];
      #  ra.rdnss = [ "2001:608:a01:4::12" ];
      #  fastdConfigs = let
      #    secret = secrets.fastd.gwu02.secret;
      #    listenAddresses = [ "195.30.94.27" "[2001:608:a01::1]" ];
      #  in {
      #    mesh0 = {
      #      inherit secret listenAddresses;
      #      listenPort = 10011;
      #      mtu = 1426;
      #    };
      #    mesh1 = {
      #      inherit secret listenAddresses;
      #      listenPort = 10089;
      #      mtu = 1426;
      #    };
      #    mesh3 = {
      #      inherit secret listenAddresses;
      #      listenPort = 10015;
      #      mtu = 1280;
      #    };
      #    mesh4 = {
      #      inherit secret listenAddresses;
      #      listenPort = 10085;
      #      mtu = 1280;
      #    };
      #  };
      #  portBalancings = [
      #    { from = 10011; to = 10089; }
      #    { from = 10015; to = 10085; }
      #  ];
      #};
     };
  };

  networking = {
    hostName = "falterturm";
    interfaces.enp0s3 = {
      ip4 = [ { address = "188.68.56.228"; prefixLength = 22; } ];
      #wir haben hier kein ipv6
      #ip6 = [ { address = "2001:608:a01::1"; prefixLength = 64; } ];
    };
    interfaces.heipv6 = {
    #  ip4 = [ { address = "195.30.94.49"; prefixLength = 28; } ];
    # nur Ipv6 
    ip6 = [ { address = "2001:470:5035::1"; prefixLength = 64; } ];
    };
    defaultGateway = "188.68.56.3";
    defaultGateway6 = "2001:608:a01::ffff";
    #verstehe ich zum großteil im Kontext nicht.
    firewall.extraCommands = ''
      ip46tables -I nixos-fw 3 -i enp0s3 -p tcp --dport 655 -j nixos-fw-accept
      ip46tables -I nixos-fw 3 -i enp0s3 -p udp --dport 655 -j nixos-fw-accept
      ip46tables -I FORWARD 1 -i tun0 -o br-ffkt -j ACCEPT
      ip46tables -I FORWARD 1 -i br-ffkt -o tun0 -j ACCEPT
    '';
    #  ip6tables -I nixos-fw 3 -i tinc.backbone -m pkttype --pkt-type multicast -j nixos-fw-accept
    #  ip46tables -I FORWARD 1 -i enp0s3 -o tinc.backbone -j ACCEPT
    #  ip46tables -I FORWARD 1 -i tinc.backbone -o enp0s3 -j ACCEPT
    #  ip46tables -I FORWARD 1 -i br0 -o tinc.backbone -j ACCEPT
    #  ip46tables -I FORWARD 1 -i tinc.backbone -o br0 -j ACCEPT
    
  };
  
  #babel und tinc haben wir noch nicht aktiv
  # environment.systemPackages = with pkgs; [
  #   tinc_pre babeld
  # ];

  #services = {
  #  tinc.networks = {
  #    backbone = {
  #      package = pkgs.tinc_pre;
  #      interfaceType = "tap";
  #      listenAddress = "188.68.56.228;
  #      extraConfig = ''
  #        Mode = switch
  #        ExperimentalProtocol = yes
  #      '';
  #    };
  #  };
  #};

  #systemd.services = {
  #  babeld = let
  #    babeldConf = pkgs.writeText "babeld.conf" ''
  #      redistribute ip ::/0 le 0 proto 3 metric 128
  #      redistribute ip 2001:608:a01::/48 le 127 metric 128
  #      redistribute ip fdef:ffc0:4fff::/48 le 127 metric 128
  #      redistribute local deny
  #      redistribute deny
  #      in ip 0.0.0.0/32 le 0 deny
  #      in ip ::/128 le 0 deny
  #    '';
  #    in {
  #      description = "Babel routing daemon";
  #      wantedBy = [ "network.target" "multi-user.target" ];
  #      after = [ "tinc.backbone" ];
  #      serviceConfig = {
  #        ExecStart =
  #          "${pkgs.babeld}/bin/babeld -c ${babeldConf} tinc.backbone";
  #      };
  #    };
  #};

  services.openvpn.servers = secrets.openvpn;

  users.extraUsers.root.password = secrets.rootPassword;
  
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";
}

