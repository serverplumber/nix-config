{
  description = "laptop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Scrollable-tiling compositor. This flake's module deliberately disables
    # the nixpkgs `programs.niri` module — do not enable both.
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOTE: deliberately NOT following nixpkgs. Upstream advises against it:
    # overriding the pinned nixpkgs invalidates every hyprland.cachix.org hit
    # and you end up compiling Hyprland and its dependencies locally.
    hyprland.url = "github:hyprwm/Hyprland";

    # Declarative bubblewrap sandboxing for nixpkgs packages — flatpak's
    # security model without flatpak's separate store. See package-migration.md
    # §1c for which apps are wrapped and why.
    nixpak = {
      url = "github:nixpak/nixpak";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Desktop shell — bar, launcher, notifications, lockscreen, wallpaper.
    # Shared by both compositors. v5 is a standalone native app; it no longer
    # needs the Quickshell runtime.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Everything that is NOT specific to this physical machine. Shared by the
      # bare-metal config and the VM config; the difference between them is
      # exactly ./hosts/laptop/machine.nix.
      commonModules = [
        ./hosts/laptop
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };

          # /home is a carried-over subvolume full of pre-existing dotfiles.
          # Without this, home-manager aborts on the first file it would
          # clobber instead of moving it aside.
          home-manager.backupFileExtension = "hm-bak";

          home-manager.users.stablefly = import ./home;
        }
      ];
    in
    {
      nixosConfigurations = {
        ### the real machine
        laptop = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [ ./hosts/laptop/machine.nix ];
        };

        ### same desktop, no real disks — `just vm`
        laptop-vm = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            (
              { ... }:
              {
                # The VM needs *a* bootloader and *a* root, and must not
                # inherit the GRUB/ESP/UUID setup from machine.nix.
                boot.loader.grub.enable = false;
                fileSystems."/" = {
                  device = "/dev/disk/by-label/nixos";
                  fsType = "ext4";
                };

                virtualisation.vmVariant.virtualisation = {
                  memorySize = 8192;
                  cores = 4;
                  # Needed for any of the compositors to get a display.
                  qemu.options = [
                    "-vga virtio"
                    "-display gtk,gl=on"
                  ];
                };
              }
            )
          ];
        };

        ### bootable live installer carrying this flake — `just iso`
        installer = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            (
              { pkgs, ... }:
              {
                nixpkgs.config.allowUnfree = true;

                # The flake travels on the ISO, so the install does not depend
                # on cloning anything. Mounted at /etc/nixos on the live system.
                environment.etc."nixos".source = self;

                environment.systemPackages = with pkgs; [
                  git
                  helix
                  gptfdisk
                  btrfs-progs
                ];

                # Flakes must be usable from the live environment itself.
                nix.settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];

                ### this is the knob that trades ISO size for offline install
                # isoImage.storeContents = [ self.nixosConfigurations.laptop.config.system.build.toplevel ];
              }
            )
          ];
        };
      };

      ### home-manager standalone — usable on any machine with nix, incl. macOS
      homeConfigurations.stablefly = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home ];
      };

      ### `nix develop` / `just shell`
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt-rfc-style
          nix-tree
          just
        ];
      };

      ### `nix fmt`
      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
