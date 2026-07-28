# Porydaw

[![Actions Status](https://github.com/huderlem/porydaw/workflows/Build/badge.svg)](https://github.com/huderlem/porydaw/actions)

A music editor for the Pokémon generation 3 decompilation projects ([pokeruby][pokeruby], [pokeemerald][pokeemerald], and [pokefirered][pokefirered]).

In Porydaw, load your decomp project directory to load the music-related project data. Then, play, edit, and create music. It sounds just like it does in-game.  When saving, Porydaw writes and creates the necessary files directly into the decomp project.  It also supports importing MIDI files, making it easy to whip up songs and voicegroups for brand new songs.

Porydaw is designed for both music beginners and power users who are familiar with DAW programs.  If you've used Sappy or Anvil Studio for your musical needs in the past, then Porydaw is for you!  If you're a power user who loves your existing DAW (FL Studio, Reaper, etc.), give Porydaw a try--but if you can't be pulled away, the [poryaaaa CLAP plugin](https://github.com/huderlem/poryaaaa) helps serve that power-user workflow.

View the [Changelog][changelog] to see what's new.


## Building

Requires CMake 3.21+, a C11/C++17 compiler, and Qt 6 (Widgets).

```sh
git clone --recursive https://github.com/huderlem/porydaw.git
cd porydaw
cmake -B build
cmake --build build
```

If you cloned without `--recursive`, run `git submodule update --init` first.

## License

Porydaw is licensed under [GPL-3.0](LICENSE). The embedded poryaaaa engine is
licensed under MIT.

## AI Disclaimer

Porydaw's code has been built with heavy usage of Claude Code--bootstrapped with the Fable model.

[pokeruby]: https://github.com/pret/pokeruby
[pokeemerald]: https://github.com/pret/pokeemerald
[pokefirered]: https://github.com/pret/pokefirered
[changelog]: https://github.com/huderlem/porydaw/blob/main/CHANGELOG.md
