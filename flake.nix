{
  description = "A Nix-flake-based Node.js development environment";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
      });
    in
    {
      overlays.default = final: prev: rec {
        nodejs = prev.nodejs;
        yarn = (prev.yarn.override { inherit nodejs; });
      };

      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ node2nix nodejs nodePackages.pnpm yarn ];
        };

        dockerImage = pkgs.dockerTools.buildImage {
          name = "neurogarden";
          tag = "latest";
          fromImage = "node:20";

          contents = [ pkgs.git ];
          extraCommands = ''
            git clone https://github.com/timkoval/neurogarden.git
            npm ci
          '';
          config = {
            Cmd = [ "npx quartz build --serve" ];
            WorkingDir = "/app";
          };


        }
      });
    };
}
