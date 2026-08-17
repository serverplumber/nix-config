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

    # Apple Music desktop client. Ships its own flake, so this needs no
    # packaging work — see package-migration.md §5c. Free (BlueOak-1.0.0),
    # unlike Cider, which went commercial: nixpkgs dropped the original
    # `cider` in July 2026 and `cider-2` is unfree.
    sidra = {
      url = "github:wimpysworld/sidra";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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

    # Declarative Plasma settings. Pulled in for exactly one reason: the
    # SD-card backup binds (modules/sdbackup.nix) have to exist in all three
    # sessions, and Plasma's shortcuts live in kglobalshortcutsrc, which Plasma
    # rewrites at runtime — so seeding it with home.file would silently drift.
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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

          # plasma-manager is a home-manager module, and modules/sdbackup.nix
          # sets programs.plasma.* through home-manager.users — so it has to be
          # available to every user config, not imported from home/.
          home-manager.sharedModules = [ inputs.plasma-manager.homeModules.plasma-manager ];

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

                # NixOS's qemu-vm.nix replaces services.xserver.videoDrivers
                # with mkVMOverride [...], which strips "nvidia" — and the
                # container toolkit then trips its own assertion:
                #
                #   `nvidia-container-toolkit` requires nvidia drivers
                #
                # Only shows up under system.build.vm, not the plain toplevel.
                # There is no GPU to pass through in a VM anyway, so turn it
                # off rather than suppressing the assertion.
                hardware.nvidia-container-toolkit.enable = nixpkgs.lib.mkForce false;
                fileSystems."/" = {
                  device = "/dev/disk/by-label/nixos";
                  fsType = "ext4";
                };

                virtualisation.vmVariant.virtualisation = {
                  memorySize = 8192;
                  cores = 4;
                  # NO GL. Two attempts, both failed:
                  #
                  #   qemu: GtkGLArea console lacks DMABUF support
                  #   epoxy_get_proc_address: Assertion `Couldn't find
                  #   current GLX or EGL context' failed   -> SIGABRT
                  #
                  # Passing --device /dev/dri into the container is NOT
                  # sufficient: the device nodes appear, but ghcr.io/nixos/nix
                  # ships no Mesa/EGL userspace, so QEMU's GTK cannot create
                  # an EGL context to begin with. Bind-mounting Fedora's Mesa
                  # from the host would mean mixing its glibc with nixpkgs'
                  # QEMU — not worth it.
                  #
                  # CONSEQUENCE: niri cannot be tested in this VM. It refuses
                  # software EGL ("software EGL renderers are skipped"), so it
                  # loads its config, opens its Wayland socket, and renders
                  # nothing. That is a VM limitation, not a config fault — the
                  # Iris Xe provides EGL natively on bare metal.
                  #
                  # Hyprland and Plasma tolerate llvmpipe and DO test here.
                  qemu.options = [
                    "-vga virtio"
                    "-display gtk"
                  ];
                };

                # NB: `services.greetd.settings.initial_session` was here
                # briefly as a diagnostic — it auto-logs straight into a
                # session and so SKIPS THE GREETER ENTIRELY, every boot, not
                # just once. Useful for capturing a compositor's journal,
                # useless for testing the login screen. Removed; re-add
                # temporarily if a session needs interrogating again.

                # Debug affordance for the VM only: root autologin on the
                # serial console, so boot problems can be interrogated by
                # script instead of by squinting at a QEMU window.
                services.getty.autologinUser = "root";

                # Mirror the console to the serial port as well as the screen,
                # so `QEMU_OPTS=-serial stdio just run-vm` gives a readable
                # boot log. Diagnosing a blank greeter from a screenshot is
                # hopeless; from a journal it is easy.
                boot.kernelParams = [
                  "console=tty0"
                  "console=ttyS0,115200n8"
                ];
                virtualisation.vmVariant.virtualisation = {
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

            # Without this the LIVE ISO has only cache.nixos.org, so
            # `nixos-install --flake .#laptop` compiles Hyprland and CUDA
            # torch during the migration itself — the worst possible moment.
            ./modules/caches.nix

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
        modules = [
          # Only the standalone path needs this. Under nixosConfigurations,
          # niri-flake's NixOS module imports the HM module itself, and adding
          # it here too declares every niri option twice. See home/niri.nix.
          inputs.niri.homeModules.niri
          ./home
        ];
      };

      ### `nix develop` / `just shell`
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixfmt
          nix-tree
          just
        ];
      };

      ### `nix fmt`
      formatter.${system} = pkgs.nixfmt;
    };
}
