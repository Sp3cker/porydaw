# Bundled-at-build MP3 encoder (LAME)

Song MP3 export encodes through `libmp3lame` from the LAME project, fetched
as source at configure time and built statically into the app. There is no
system, Homebrew, `dlopen`, or FFmpeg runtime dependency.

| Field | Value |
|---|---|
| Project | [LAME](https://lame.sourceforge.io/) (`www.mp3dev.org`) |
| Version | 3.100 (13 October 2017) |
| Fetched from | `https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz` |
| Pin | `SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`, wired in `cmake/Lame.cmake` |
| License | GNU Library General Public License v2 (LGPL-2.0); see `COPYING` in the fetched source |
| Built subset | The 20 `libmp3lame/*.c` encoder sources, encoder-only (`HAVE_MPGLIB` unset, no NASM/SSE assembly), with a generated configure-equivalent `config.h` (`cmake/lame_config.h.in`) |
| Modifications | None to upstream sources; only the `LameMp3` CMake target wiring in `cmake/Lame.cmake` |
| Used as | Fixed stereo 320 kbps CBR via `src/audio/mp3_encode.{h,c}` (`pd_mp3_*`) |

## Relink and source obligations (LGPL-2.0, static link)

- The complete corresponding LAME source is the tarball above, fetched
  automatically by the build (`FetchContent` in `cmake/Lame.cmake`); keep
  that pin and URL working so every distributed binary maps to its source.
- A user can rebuild or swap the encoder and relink: `cmake/Lame.cmake`
  is the single wiring point, the compiled objects live in the CMake build
  tree under the `LameMp3` target, and the app links it through
  `porydaw_native_host`.
- Preserve this notice and the LAME acknowledgment (`LICENSE` in the LAME
  source asks for acknowledgment plus a link to `www.mp3dev.org`).
- Publish back any modifications made to LAME itself under the LGPL.
