# Motivation
The goal of `copy-non-store-tarball` is to aid in finding and preserving
non-nixpkgs dependencies a flake or some other nix derivation depends on.  
These dependencies are especially crucial because they are usually exempt from
being cached or preserved on `cache.nixos.org` and `tarballs.nixos.org`, so once
their source disappears, they have to be added manually, or the derivation that
depends on them can not be built.  
My personal usecase for this are nightly builds of `zig`, which can be
downloaded from the official server using [this zig
overlay](https://github.com/mitchellh/zig-overlay), but since the official
server removes non-release builds older than a few weeks, this quickly leads to
(naively) unbuildable derivations.

# Functionality
`copy-non-store-tarball` requires a nix derivation and a rclone-compatible
destination as inputs. The derivations' dependencies are searched for fixed
output derivations (the results of eg. a `fetchurl`), and those are filtered to
those FODs that are not cached on `cache.nixos.org` or `tarballs.nixos.org`
(this is a useful property because the nix team [seems concerned with keeping
FODs accessible
indefinitely](https://discourse.nixos.org/t/upcoming-garbage-collection-for-cache-nixos-org/39078#garbage-collection-policy-and-implications-2),
so those don't have to be preserved manually).
These FODs are then either downloaded or copied from the local nix store to the
rclone-compatible destination in a format compatible with the content-addressed
tarball-archive at [tarballs.nixos.org](tarballs.nixos.org), which `fetchurl`
can fall back to if all urls are inaccessible.

# Usage
The first argument is a nix derivation, the second the destination which will
contain the tarballs, and the third, optional, argument contains flags
passed to `rclone`.
```bash
copy-non-store-tarballs .#default /srv/http/tarballs
```
or
```bash
copy-non-store-tarballs /run/current-system s3-bucket:/bucketname '-P --config ./rclone.conf'
```

# Using the tarballs
In order to use the archived tarballs in a build, the `impureEnvVar`
`NIX_HASHED_MIRRORS` has to be passed to the `nix build` that builds the
derivation. If the archive exists at `tarballs.myhostname.com`, this looks like

```bash
sudo NIX_HASHED_MIRRORS="tarballs.myhostname.com" nix build ".#default"
```
The sudo is likely necessary because otherwise the build is relegated to the
`nix-daemon`, which does not have `NIX_HASHED_MIRRORS` in its environment. An
alternative, of course, is to modify the service to include this variable.

# Completeness
This tool supports FODs with hash method `nar`, `flat`, and `text` (the latter
of which is handled exactly like `flat`, which seems like the right thing to
do?). `nar` only supports sources that are single archives which can be
extracted with `tar`.
