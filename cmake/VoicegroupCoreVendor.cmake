set(PORYDAW_VOICEGROUP_CORE_VENDOR_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/voicegroup-core"
    CACHE PATH "Path to vendored voicegroup-core artifacts")

set(_vg_expected_source_commit "f23020d53240f51535865fc2cc1f6005c44dbdf4")
set(_vg_expected_abi "2")
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _vg_processor)

if(APPLE)
    if(CMAKE_OSX_ARCHITECTURES)
        list(LENGTH CMAKE_OSX_ARCHITECTURES _vg_arch_count)
        if(NOT _vg_arch_count EQUAL 1)
            message(FATAL_ERROR
                "voicegroup-core architecture mismatch: universal Apple builds are not supported")
        endif()
        list(GET CMAKE_OSX_ARCHITECTURES 0 _vg_processor)
        string(TOLOWER "${_vg_processor}" _vg_processor)
    endif()
    if(_vg_processor MATCHES "^(arm64|aarch64)$")
        set(_vg_target "aarch64-apple-darwin")
        set(_vg_architecture "aarch64")
    elseif(_vg_processor MATCHES "^(x86_64|amd64)$")
        set(_vg_target "x86_64-apple-darwin")
        set(_vg_architecture "x86_64")
    else()
        message(FATAL_ERROR
            "voicegroup-core architecture mismatch: unsupported Apple processor '${CMAKE_SYSTEM_PROCESSOR}'")
    endif()
elseif(WIN32)
    if(NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
        message(FATAL_ERROR
            "voicegroup-core target mismatch: Windows requires the x64 MSVC toolchain")
    endif()
    set(_vg_target "x86_64-pc-windows-msvc")
    set(_vg_architecture "x86_64")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    if(NOT _vg_processor MATCHES "^(x86_64|amd64)$")
        message(FATAL_ERROR
            "voicegroup-core architecture mismatch: unsupported Linux processor '${CMAKE_SYSTEM_PROCESSOR}'")
    endif()
    set(_vg_target "x86_64-unknown-linux-gnu")
    set(_vg_architecture "x86_64")
else()
    message(FATAL_ERROR
        "voicegroup-core target mismatch: unsupported system '${CMAKE_SYSTEM_NAME}'")
endif()

set(_vg_manifest
    "${PORYDAW_VOICEGROUP_CORE_VENDOR_DIR}/lib/${_vg_target}/manifest.json")
if(NOT EXISTS "${_vg_manifest}")
    message(FATAL_ERROR
        "voicegroup-core target mismatch: missing manifest for '${_vg_target}'")
endif()
file(READ "${_vg_manifest}" _vg_manifest_json)

function(_porydaw_voicegroup_manifest_get output key)
    string(JSON _value ERROR_VARIABLE _error GET "${_vg_manifest_json}" "${key}")
    if(NOT _error STREQUAL "NOTFOUND")
        message(FATAL_ERROR
            "voicegroup-core manifest error: cannot read '${key}' from '${_vg_manifest}': ${_error}")
    endif()
    set(${output} "${_value}" PARENT_SCOPE)
endfunction()

_porydaw_voicegroup_manifest_get(_vg_manifest_target target_triple)
_porydaw_voicegroup_manifest_get(_vg_manifest_arch architecture)
_porydaw_voicegroup_manifest_get(_vg_manifest_source source_commit)
_porydaw_voicegroup_manifest_get(_vg_manifest_abi abi_version)
_porydaw_voicegroup_manifest_get(_vg_manifest_header header)
_porydaw_voicegroup_manifest_get(_vg_manifest_header_hash header_sha256)
_porydaw_voicegroup_manifest_get(_vg_manifest_library library)
_porydaw_voicegroup_manifest_get(_vg_manifest_library_hash lib_sha256)

if(NOT _vg_manifest_target STREQUAL _vg_target)
    message(FATAL_ERROR
        "voicegroup-core target mismatch: selected '${_vg_target}', manifest says '${_vg_manifest_target}'")
endif()
if(NOT _vg_manifest_arch STREQUAL _vg_architecture)
    message(FATAL_ERROR
        "voicegroup-core architecture mismatch: selected '${_vg_architecture}', manifest says '${_vg_manifest_arch}'")
endif()
if(NOT _vg_manifest_source STREQUAL _vg_expected_source_commit)
    message(FATAL_ERROR
        "voicegroup-core source mismatch: expected '${_vg_expected_source_commit}', manifest says '${_vg_manifest_source}'")
endif()
if(NOT _vg_manifest_abi STREQUAL _vg_expected_abi)
    message(FATAL_ERROR
        "voicegroup-core ABI mismatch: expected '${_vg_expected_abi}', manifest says '${_vg_manifest_abi}'")
endif()

set(_vg_header "${PORYDAW_VOICEGROUP_CORE_VENDOR_DIR}/${_vg_manifest_header}")
set(_vg_library "${PORYDAW_VOICEGROUP_CORE_VENDOR_DIR}/${_vg_manifest_library}")
if(NOT EXISTS "${_vg_header}")
    message(FATAL_ERROR "voicegroup-core header checksum mismatch: header is missing")
endif()
if(NOT EXISTS "${_vg_library}")
    message(FATAL_ERROR "voicegroup-core archive checksum mismatch: archive is missing")
endif()
file(SHA256 "${_vg_header}" _vg_actual_header_hash)
file(SHA256 "${_vg_library}" _vg_actual_library_hash)
if(NOT _vg_actual_header_hash STREQUAL _vg_manifest_header_hash)
    message(FATAL_ERROR
        "voicegroup-core header checksum mismatch: expected '${_vg_manifest_header_hash}', got '${_vg_actual_header_hash}'")
endif()
if(NOT _vg_actual_library_hash STREQUAL _vg_manifest_library_hash)
    message(FATAL_ERROR
        "voicegroup-core archive checksum mismatch: expected '${_vg_manifest_library_hash}', got '${_vg_actual_library_hash}'")
endif()

set(_vg_system_libraries)
if(WIN32)
    # Rust's MSVC staticlib leaves the Windows imports it uses for the final
    # consumer to link, just like a C/C++ static library.
    list(APPEND _vg_system_libraries ws2_32 userenv ntdll)
endif()

set(_vg_probe_dir "${CMAKE_BINARY_DIR}/voicegroup-core-abi-probe")
file(MAKE_DIRECTORY "${_vg_probe_dir}")
set(_vg_probe_source "${_vg_probe_dir}/probe.c")
file(WRITE "${_vg_probe_source}" [=[
#include <voicegroup_core.h>
_Static_assert(VOICEGROUP_CORE_ABI_VERSION == 2, "voicegroup-core ABI constant mismatch");
int main(void) {
    return voicegroup_core_abi_version() == VOICEGROUP_CORE_ABI_VERSION ? 0 : 1;
}
]=])
try_compile(_vg_probe_ok
    "${_vg_probe_dir}/build"
    SOURCES "${_vg_probe_source}"
    CMAKE_FLAGS
        "-DCMAKE_C_STANDARD=11"
        "-DINCLUDE_DIRECTORIES=${PORYDAW_VOICEGROUP_CORE_VENDOR_DIR}/include"
    LINK_LIBRARIES "${_vg_library}" ${_vg_system_libraries}
    OUTPUT_VARIABLE _vg_probe_output)
if(NOT _vg_probe_ok)
    message(FATAL_ERROR
        "voicegroup-core ABI link probe failed for '${_vg_target}':\n${_vg_probe_output}")
endif()

add_library(voicegroup_core_static STATIC IMPORTED GLOBAL)
set_target_properties(voicegroup_core_static PROPERTIES
    IMPORTED_LOCATION "${_vg_library}"
    INTERFACE_INCLUDE_DIRECTORIES "${PORYDAW_VOICEGROUP_CORE_VENDOR_DIR}/include"
    INTERFACE_LINK_LIBRARIES "${_vg_system_libraries}")
set(PORYDAW_VOICEGROUP_CORE_TARGET "${_vg_target}")
