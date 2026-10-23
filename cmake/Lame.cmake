include_guard(GLOBAL)

# Bundled-at-build LAME MP3 encoder (libmp3lame 3.100, LGPL-2.0; see external/lame-LICENSES.md).
# Portable encoder-only source build with a generated configure-equivalent config.h.
include(FetchContent)
FetchContent_Declare(LameUpstream
    URL https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    URL_HASH SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_Populate(LameUpstream)
# Every encoder unit includes <config.h>; generate ours from the template so
# the IEEE typedefs and feature macros match what autoconf would emit.
configure_file(
    "${CMAKE_SOURCE_DIR}/cmake/lame_config.h.in"
    "${CMAKE_BINARY_DIR}/lame-config/config.h"
    COPYONLY
)

set(lame_sources
    "${lameupstream_SOURCE_DIR}/libmp3lame/VbrTag.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/bitstream.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/encoder.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/fft.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/gain_analysis.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/id3tag.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/lame.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/newmdct.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/presets.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/psymodel.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/quantize.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/quantize_pvt.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/reservoir.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/set_get.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/tables.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/takehiro.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/util.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/vbrquantize.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/version.c"
    "${lameupstream_SOURCE_DIR}/libmp3lame/mpglib_interface.c"
)
add_library(LameMp3 STATIC ${lame_sources})
target_include_directories(LameMp3 PUBLIC
    "${lameupstream_SOURCE_DIR}/include"
)
target_include_directories(LameMp3 PRIVATE
    "${lameupstream_SOURCE_DIR}/libmp3lame"
    "${lameupstream_SOURCE_DIR}/mpglib"
    "${CMAKE_BINARY_DIR}/lame-config"
)
# Feature macros and IEEE typedefs now come from the generated config.h, the
# same path configured builds take; HAVE_CONFIG_H selects its inclusion.
target_compile_definitions(LameMp3 PRIVATE HAVE_CONFIG_H)
# Keep export-time encoding responsive even when the host builds Debug.
target_compile_options(LameMp3 PRIVATE
    $<$<AND:$<CONFIG:Debug>,$<NOT:$<C_COMPILER_ID:MSVC>>>:-O2>
    $<$<AND:$<CONFIG:Debug>,$<C_COMPILER_ID:MSVC>>:/O2>
)
