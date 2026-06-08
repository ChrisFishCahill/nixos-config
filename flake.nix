{
  description = "A simple R project";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            blas   = prev.blas.override   { blasProvider   = final.openblas; };
            lapack = prev.lapack.override { lapackProvider = final.openblas; };
          })
        ];
      };
      rEnv = pkgs.rWrapper.override {
        packages = with pkgs.rPackages; [ RTMB sdmTMB tidyverse ];
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ rEnv ];
      };
    };
}
