{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
      imageName = "neurogarden";
      imageTag = "latest";
      mkDockerImage =
        pkgs: targetSystem:
        let
          archSuffix = if targetSystem == "x86_64-linux" then "amd64" else "arm64";
          gardenContents = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = ./.;
          };
        in
        pkgs.dockerTools.buildImage {
          name = imageName;
          tag = "${imageTag}-${archSuffix}";
          copyToRoot = pkgs.buildEnv {
            name = "app-root";
            paths = [ gardenContents pkgs.nodejs_20 ];
            pathsToLink = [ "/" "/bin" ];
          };
          extraCommands = ''
              export HOME=$(mktemp -d)
              export PATH="$PATH:$(pwd)/bin"
              npm set strict-ssl=false  
              npm ci
            '';
          config = {
            Cmd = [ "/bin/npx quartz build --serve" ];
          };
        };
    in
    {
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
          "amd64" = buildForLinux "x86_64-linux";
          "arm64" = buildForLinux "aarch64-linux";
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
              nix build .#amd64 --out-link result-${system}-amd64
              # echo "Building aarch64-linux image..."
              # nix build .#arm64 --out-link result-${system}-arm64
            ''
          );
        };
      });
    };
}
