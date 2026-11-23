{
  description = "The browser of Strix: Chromium pages in a window drawn with StrixUI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = rec {
        default = pkgs.callPackage ./nix/package.nix { };
        inherit (default) quickshell-webengine;
      };

      overlays.default = final: _: {
        strix-browser = final.callPackage ./nix/package.nix { };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.git-cliff ];
        shellHook = ''
          git config core.hooksPath .githooks
        '';
      };
    };
}
