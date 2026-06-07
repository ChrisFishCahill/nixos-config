{ config, pkgs, lib, ... }:

let
  # ------------------------------------------------------------------ #
  # unigd: graphics device backend for httpgd, not in nixpkgs           #
  # ------------------------------------------------------------------ #
  unigd = pkgs.rPackages.buildRPackage {
    name = "unigd";
    src = pkgs.fetchFromGitHub {
      owner = "nx10";
      repo = "unigd";
      rev = "v0.2.0";
      sha256 = "sha256-im8NFP6ZAHAs6yv3D9ENgOT1YGLFvZNoa1t9ba1zTCo=";
    };
    propagatedBuildInputs = with pkgs; [
      rPackages.cpp11 rPackages.systemfonts
      cairo libtiff libpng zlib
    ];
  };

  # ------------------------------------------------------------------ #
  # httpgd: browser-based R graphics device, not in nixpkgs             #
  # ------------------------------------------------------------------ #
  httpgd = pkgs.rPackages.buildRPackage {
    name = "httpgd";
    src = pkgs.fetchFromGitHub {
      owner = "nx10";
      repo = "httpgd";
      rev = "v2.1.4";
      sha256 = "sha256-aEhrcWmDaqZn+fBHX/9/9VyJhYeHQKSSLaxeMQhzApA=";
    };
    propagatedBuildInputs = with pkgs; [
      rPackages.Rcpp rPackages.later rPackages.promises
      rPackages.cpp11 rPackages.AsioHeaders
      unigd cairo libpng zlib
    ];
  };

  # ------------------------------------------------------------------ #
  # admb: AD Model Builder, compiled from source                        #
  # pinned to main — update sha256 if the build breaks                  #
  # ------------------------------------------------------------------ #
  admb = pkgs.stdenv.mkDerivation {
    name = "admb";
    src = pkgs.fetchFromGitHub {
      owner = "admb-project";
      repo = "admb";
      rev = "main";
      sha256 = "sha256-NCKxp8nm3zXXBwt74Wym3H1eoUpwvo06t4/UFNY7asI=";
    };
    buildInputs = with pkgs; [ gcc gnumake flex bison bashInteractive ];
    buildPhase = ''
      make CFLAGS="-Wno-format-security" CXXFLAGS="-Wno-format-security" g++-core
    '';
    installPhase = ''
      mkdir -p $out
      cp -r build/admb/* $out/
    '';
  };

  # ------------------------------------------------------------------ #
  # quarto pinned to 1.8.x — 1.9.37 in nixpkgs has a                   #
  # syntax-highlighting bug                                             #
  # ------------------------------------------------------------------ #
  quarto = let
    oldpkgs = import (fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/nixos-24.11.tar.gz";
      sha256 = "sha256:1s2gr5rcyqvpr58vxdcb095mdhblij9bfzaximrva2243aal3dgx";
    }) {};
  in oldpkgs.quarto;

  # ------------------------------------------------------------------ #
  # R environment with all packages bundled                             #
  # ------------------------------------------------------------------ #
  rEnv = pkgs.rWrapper.override {
    packages = with pkgs.rPackages; [
      # TMB stack
      RTMB Matrix numDeriv codetools
      sdmTMB fmesher sf glmmTMB

      # Stan
      tmbstan
      bayesplot
      # cmdstanr: not in nixpkgs, install once per user manually:
      # Rscript -e "install.packages('cmdstanr',
      #   repos=c('https://stan-dev.r-universe.dev',
      #           'https://cloud.r-project.org'))"

      # Occupancy / abundance
      unmarked

      # Stats
      nlme mgcv tidyverse

      # Testing
      tinytest testthat

      # Dev / IDE
      devtools remotes styler languageserver

      # Graphics (custom derivations above)
      unigd httpgd
    ];
  };

in {
  imports = [ ./hardware-configuration.nix ];

  # ------------------------------------------------------------------ #
  # Boot — keep grub as the installer set it up                         #
  # ------------------------------------------------------------------ #
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  # ------------------------------------------------------------------ #
  # Networking                                                          #
  # ------------------------------------------------------------------ #
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------------ #
  # Locale / time                                                       #
  # ------------------------------------------------------------------ #
  time.timeZone = "America/Detroit";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # ------------------------------------------------------------------ #
  # Desktop                                                             #
  # ------------------------------------------------------------------ #
  services.xserver.enable = false;
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };
  services.greetd = {
    enable = true;
    settings.default_session = {
    command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
      user = "greeter";
    };
  };
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];

  # ------------------------------------------------------------------ #
  # Audio                                                               #
  # ------------------------------------------------------------------ #
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ------------------------------------------------------------------ #
  # Users                                                               #
  # ------------------------------------------------------------------ #
  users.users."cc" = {
    isNormalUser = true;
    description = "Chris";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
  };

  # ------------------------------------------------------------------ #
  # Nix settings                                                        #
  # ------------------------------------------------------------------ #
  nixpkgs.config.allowUnfree = true;
  # Note: parallel OpenBLAS is the default in nixpkgs — no overlay needed

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  # so sudo nixos-rebuild switch works without the full path
  security.sudo.extraConfig = "Defaults env_keep+=PATH";

  # auto garbage collect old generations weekly
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ------------------------------------------------------------------ #
  # Git                                                                 #
  # ------------------------------------------------------------------ #
  programs.git = {
    enable = true;
    config = {
      user.name = "ChrisFishCahill";
      user.email = "christopherfishcahill@gmail.com";
    };
  };
  
  #-------------------------------------------------------------------- #
  # uwsm stuff
  #-------------------------------------------------------------------- #
  programs.bash.loginShellInit = ''
  if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec uwsm start hyprland-uwsm.desktop
  fi
'';

  # ------------------------------------------------------------------ #
  # Fonts                                                               #
  # ------------------------------------------------------------------ #
  fonts.packages = with pkgs; [
    nerd-fonts.sauce-code-pro
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];

  # ------------------------------------------------------------------ #
  # System packages — available to all users                            #
  # ------------------------------------------------------------------ #
  environment.systemPackages = with pkgs; [
    # R
    rEnv admb openblas lapack

    # Build tools (needed for compiling R packages from source)
    gcc gnumake flex bison cmake clang-tools pkg-config

    # System libraries
    git curl openssl zlib libxml2

    # CLI
    vim neovim bat tealdeer tmux htop ripgrep nodejs openssh
    fastfetch pandoc quarto tree-sitter fd chezmoi greetd tuigreet

    # GUI
    mullvad zotero libreoffice foliate rofi ghostty remmina forgejo
    firefox rstudio kdePackages.okular adwaita-icon-theme
  ];

  # ------------------------------------------------------------------ #
  # Shell aliases                                                       #
  # ------------------------------------------------------------------ #
  environment.shellAliases = {
    vim = "nvim";
  };

  # ------------------------------------------------------------------ #
  # Environment variables — applied to all users' shells                #
  # ------------------------------------------------------------------ #
  environment.variables = {
    # suppress noisy format-security warnings when compiling R packages
    CFLAGS   = "-Wno-format-security";
    CXXFLAGS = "-Wno-format-security";
  };

  # ------------------------------------------------------------------ #
  # Services                                                            #
  # ------------------------------------------------------------------ #
  services.openssh.enable = true;
  services.printing.enable = true;
  services.spice-vdagentd.enable = true;   # clipboard in VM
  services.mullvad-vpn.enable = true;

  system.stateVersion = "26.05";
}
