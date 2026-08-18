SECTIONS
{
    .rodata :
    {
        . = ALIGN(4);
        sound/songs/midi/mus_aqua_magma_hideout.o(.rodata);
        sound/songs/midi/mus_mkcheck_compare.o(.rodata);
    }
}
