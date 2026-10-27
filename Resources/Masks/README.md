# Masks

Place grayscale/alpha PNG masks here, for example:

- `celosia_variant_a.png`
- `celosia_variant_b.png`

White / opaque = foreground (drawn above the clock).  
Black / transparent = hidden.

At install time Theos should copy these to:

`/var/jb/Library/Application Support/CelosiaDepth/Masks/`

(Add a `layout/` tree in a later revision if you package masks in the deb.)
