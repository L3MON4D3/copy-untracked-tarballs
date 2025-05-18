{
  jq,
  wget,
  coreutils,
  rclone,
  writeShellApplication
}: writeShellApplication {
  name = "copy-non-store-tarballs-0.1";
  runtimeInputs = [ jq wget coreutils rclone ];
  text = builtins.readFile ./copy-non-store-tarballs.sh;
}
