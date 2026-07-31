# Installation

## Prerequisites

To use Porydaw, you need a fully-setup Gen 3 decomp project ([pokeruby][pokeruby], [pokeemerald][pokeemerald], or [pokefirered][pokefirered]).

Porydaw has no other dependencies to run it.  Simply [download the prebuilt Windows, macOS, or Linux release](https://github.com/huderlem/porydaw/releases) and run the `porydaw` executable.
!!! tip
    If your decomp project lives in WSL, I recommend using the Windows release. However, if for some reason the Windows release loads files too slowly, you can use the Linux version instead.

## Windows

1. Download the Windows .zip file: [`porydaw-windows.zip`](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-windows.zip)
2. Unzip the contents
3. Run `porydaw.exe`
4. If the SmartScreen warning apperas, click `More info -> Run anyway`

## macOS

1. Download the correct macOS .zip file, depending on your computer's chip:
    - Arm: [porydaw-macos-arm64.zip](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-arm64.zip)
    - x86_64 (Intel): [porydaw-macos-x86_64.zip](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-macos-x86_64.zip)
2. Unzip the contents
3. Open the DMG and drag to `/Applications`

Porydaw is not notarized with Apple, so macOS quarantines the downloaded
app and refuses to launch it. (The warning claims the app is "damaged". It isn't, this is just how macOS treats any app that isn't notarized.)

After installing, remove the quarantine flag by hand:

  - Open Terminal (`Applications > Utilities > Terminal`) and run:
```
xattr -d com.apple.quarantine /Applications/porydaw.app
```
     If you put the app somewhere other than `/Applications`, change the
     path in the command to match.

## Linux

1. Download the Linux .zip file: [`porydaw-linux.zip`](https://github.com/huderlem/porydaw/releases/latest/download/porydaw-linux.zip)
2. Unzip the contents
3. Ensure the `porydaw.AppImage` is executable by running `chmod +x porydaw.AppImage`
4. Run `./porydaw.AppImage`

<!-- TODO: AppImage: chmod +x, run; FUSE note for older distros. -->

## Building from source

If you'd rather build Porydaw yourself, see [INSTALL.md](https://github.com/huderlem/porydaw/blob/main/INSTALL.md) for instructions on building Porydaw from source.

[pokeruby]: https://github.com/pret/pokeruby
[pokeemerald]: https://github.com/pret/pokeemerald
[pokefirered]: https://github.com/pret/pokefirered
