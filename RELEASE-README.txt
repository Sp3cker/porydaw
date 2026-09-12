porydaw
=======

A music editor for the Pokémon generation 3 decompilation projects ([pokeruby][pokeruby], [pokeemerald][pokeemerald], and [pokefirered][pokefirered]).

In Porydaw, load your decomp project directory to load the music-related project data. Then, play, edit, and create music. It sounds just like it does in-game.  When saving, Porydaw writes and creates the necessary files directly into the decomp project.  It also supports importing MIDI files, making it easy to whip up songs and voicegroups for brand new songs.

Porydaw is designed for both music beginners and power users who are familiar with DAW programs.  If you've used Sappy or Anvil Studio for your musical needs in the past, then Porydaw is for you!  If you're a power user who loves your existing DAW (FL Studio, Reaper, etc.), give Porydaw a try--but if you can't be pulled away, the [poryaaaa CLAP plugin](https://github.com/huderlem/poryaaaa) helps serve that power-user workflow.

macOS note:
    Porydaw is not notarized with Apple, so macOS quarantines the downloaded
    app and blocks the first launch. To allow it, run this
    in Terminal after copying the app to /Applications:
        xattr -d com.apple.quarantine /Applications/porydaw.app
    These steps are also in "RUN AFTER INSTALL.txt" inside the .dmg.
    This build uses bundle identifier com.sp3cker.porydaw and stores
    preferences under organization sp3cker, so it does not share settings
    with older huderlem releases. Rename an existing /Applications/porydaw.app
    before copying this one if you want both versions installed.

Windows note:
    Unzip this build into a new folder if you want to keep an older install.
    Preferences are stored under organization sp3cker and do not share with
    older huderlem releases.

Project home:
    https://github.com/huderlem/porydaw

Release notes:
    https://github.com/huderlem/porydaw/blob/main/CHANGELOG.md
