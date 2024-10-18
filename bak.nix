{
  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: lib.genAttrs supportedSystems (system: f system);
      # forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
      #   pkgs = import nixpkgs { inherit system; overlays = [ self.overlays.default ]; };
      # });
      imageName = "neurogarden";
      imageTag = "latest";
      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";
          
          # gardenContents = pkgs.fetchgit {
          #   url = "https://github.com/timkoval/neurogarden.git";
          #   rev = "refs/heads/v4";
          #   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          # };
          gardenContents = lib.fileset.toSource {
            root = ./.;
            fileset = ./.;
          };
        in
        pkgs.dockerTools.buildImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
        # copyToRoot = pkgs.buildEnv {
        #   name = "image-root";
        #   paths = [ pkgs.git pkgs.nodejs ./.];
        #   pathsToLink = [ "/app" "/bin"];
        # };
        copyToRoot = pkgs.buildEnv {
          name = "app-root";
          paths = [ gardenContents pkgs.nodejs_20 ];
          pathsToLink = [ "/" "/bin" ];
        };
        # contents = [ ./. ];
        extraCommands = ''
            # export HOME=$(mktemp -d)
            # export PATH="$PATH:$(pwd)/bin"
            # ls /bin || echo "notfound"
            # ls bin || echo "notfound"
            #
            # npm set strict-ssl=false  
            # npm ci
          '';
        config = {
          Cmd = [ "ls -lah" ];
        };
        };
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

      });
       
      packages = forEachSupportedSystem (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          buildForLinux =
            targetSystem:
            if system == targetSystem then
              mkDockerImage pkgs targetSystem
            else
              mkDockerImage (import nixpkgs {
                localSystem = system;
                crossSystem = targetSystem;
              }) targetSystem;
        in
        {
          "amd64-linux" = buildForLinux "x86_64-linux";
          "arm64-linux" = buildForLinux "aarch64-linux";
          "amd64-darwin" = buildForLinux "x86_64-darwin";
          "arm64-darwin" = buildForLinux "aarch64-darwin";
        }
      );

      apps = forEachSupportedSystem (system: {
        default = {
          type = "app";
          program = toString (
            nixpkgs.legacyPackages.${system}.writeScript "build-multi-arch" ''
              #!${nixpkgs.legacyPackages.${system}.bash}/bin/bash
              set -e
              echo "Building x86_64-linux image..."
              nix build .#amd64-linux --out-link result-${system}-amd64-linux
              # echo "Building aarch64-linux image..."
              # nix build .#arm64-linux --out-link result-${system}-arm64-linux
              # echo "Building x86_64-darwin image..."
              # nix build .#amd64-darwin --out-link result-${system}-amd64-darwin
              # echo "Building aarch64-darwin image..."
              # nix build .#arm64-darwin --out-link result-${system}-arm64-darwin
            ''
          );
        };
      });
    };
}
