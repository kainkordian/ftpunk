# Selected FTPunk app icon

Pixel Pursuit: the neon pixel-art cyclist, wearing a magenta cycling helmet instead of a mohawk. Edited using built-in imagegen; the exact edit prompt and historical source reference are in [prompt.json](prompt.json). The original proposals remain locally in `design/icon-proposals/`, which is excluded from Git. They are not needed to build the app or regenerate its icons; the selected source artwork below is included in the repository.

- `FTPunk-source.png`: full-resolution selected artwork, opaque square background.
- `FTPunk.icns`: Mac packaging icon.
- `App/Assets.xcassets/AppIcon.appiconset/`: iOS 1024 px icon and Mac size variants.

Regenerate mechanical size exports with `sh Tools/generate_app_icons.sh`. Both Xcode targets use the AppIcon asset; the local Mac packaging script copies the ICNS into the app bundle.
