{
  lib,
  runCommand,
  imagemagick,
}:
# A greyscale copy of an icon, as a store path to a PNG — usable directly as
# a desktop entry's `icon`. Takes the source image file; transparency is kept.
#
#   greyscaleIcon = pkgs.callPackage ../pkgs/greyscale-icon.nix { };
#   icon = "${greyscaleIcon "${pkgs.brave}/share/icons/hicolor/256x256/apps/brave-browser.png"}";
src:
let
  # A derivation name may not carry the source's store-path context.
  stem = lib.removeSuffix ".png" (builtins.unsafeDiscardStringContext (baseNameOf src));
in
runCommand "${stem}-greyscale.png" { nativeBuildInputs = [ imagemagick ]; } ''
  magick -background none ${src} -colorspace Gray PNG32:$out
''
