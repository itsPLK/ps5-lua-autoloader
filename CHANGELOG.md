# Changelog

## v1.1
- **Payload Manager (New Default ELF)**: It handles payload loading after the game app is closed, improving the stability of payloads like **etaHEN** and **kstuff**.
    - **Note on Compatibility**: Your existing autoload configurations will continue to work as they did before.
    - **Note on Usage**: If you choose to use Payload Manager, it should be the **only** item listed in your `autoload.txt`.
- **Custom ELF Loader**: The default `elfldr` now only accepts connections from the PS5 itself (localhost). This improves security by preventing other devices on your network from sending payloads to your console.
    - **Note**: You can still use a standard `elfldr` if you need to send payloads from other devices. See the **Additional Info** section in [README.md](README.md) for instructions.

## v1.0
[Full Changelog](https://github.com/itsPLK/ps5-lua-autoloader/compare/v0.9...v1.0)


## v0.9
[Full Changelog](https://github.com/itsPLK/ps5-lua-autoloader/compare/v0.8.1...v0.9)

## v0.8.1
[Full Changelog](https://github.com/itsPLK/ps5-lua-autoloader/compare/v0.8...v0.8.1)

## v0.8
[Full Changelog](https://github.com/itsPLK/ps5-lua-autoloader/compare/v0.7...v0.8)

## v0.7
- Added lapse exploit for fw above 7.61, up to 10.01 (currently unstable)
- Uses new savedata autoload method
- Added support for few more games
- Added web-menu as default payload

[Full Changelog](https://github.com/itsPLK/ps5-lua-autoloader/compare/v0.6...v0.7)