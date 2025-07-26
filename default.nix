{
  jq,
  wget,
  coreutils,
  rclone,
  writeShellApplication
}: (writeShellApplication {
  name = "copy-untracked-tarballs";
  runtimeInputs = [ jq wget coreutils rclone ];
  text = builtins.readFile ./copy-untracked-tarballs.sh;
}).overrideAttrs (old: { name = "${old.name}-0.1"; })
