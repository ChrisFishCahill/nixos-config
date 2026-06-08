{
  description = "R project dev shell — RTMB/Matrix + ADMB + httpgd, parallel OpenBLAS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # quarto pinned to 24.11 — 26.05's quarto has a syntax-highlighting bug
    nixpkgs-quarto.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, nixpkgs-quarto }:
    let
      system = "x86_64-linux";

      # parallel OpenBLAS: re-point the blas/lapack wrappers at openblas so R
      # links against it at build time (no LD_PRELOAD, no isILP64 error)
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            blas   = prev.blas.override   { blasProvider   = final.openblas; };
            lapack = prev.lapack.override { lapackProvider = final.openblas; };
          })
        ];
      };

      quarto = (import nixpkgs-quarto { inherit system; }).quarto;

      # ---- custom R packages not in nixpkgs ---------------------------- #
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

      # ---- ADMB: compiled from source ---------------------------------- #
      admb = pkgs.stdenv.mkDerivation {
        name = "admb";
        src = pkgs.fetchFromGitHub {
          owner = "admb-project";
          repo = "admb";
          rev = "main";          # pin to a tag/SHA for true reproducibility
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

      # ---- R with the libraries this project needs --------------------- #
      rEnv = pkgs.rWrapper.override {
        packages = with pkgs.rPackages; [
          RTMB Matrix   # core R libraries
          httpgd        # custom (pulls in unigd automatically)
        ];
      };

    in {
      devShells.${system}.default = pkgs.mkShell {
        # R libraries live in rEnv; tools/binaries go here
        buildInputs = [ rEnv admb quarto ];

        shellHook = ''
          export CFLAGS="-Wno-format-security"
          export CXXFLAGS="-Wno-format-security"
        '';
      };
    };
}
