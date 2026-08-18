SECTIONS
{
    .rodata :
    {
        . = ALIGN(4);
        sound/songs/midi/mus_dummy.o(.rodata);
        sound/songs/midi/mus_littleroot_test.o(.rodata);
        sound/songs/midi/mus_route101.o(.rodata);
        sound/songs/midi/mus_route102.o(.rodata);
        sound/songs/midi/mus_gsc_route38.o(.rodata);
        sound/songs/midi/mus_caught.o(.rodata);
        sound/songs/midi/mus_petalburg.o(.rodata);
        sound/songs/midi/mus_oldale.o(.rodata);
        sound/songs/midi/mus_gym.o(.rodata);
        sound/songs/midi/mus_surf.o(.rodata);
        sound/songs/midi/mus_victory_wild.o(.rodata);
        sound/songs/midi/se_use_item.o(.rodata);
        sound/songs/midi/se_pc_login.o(.rodata);
        sound/songs/midi/se_fanfare_1trk.o(.rodata);
    }
}
