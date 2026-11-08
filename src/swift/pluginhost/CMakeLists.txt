set(porydaw_pluginbridge_dir "${PROJECT_SOURCE_DIR}/src/pluginhost")

add_library(PorydawPluginBridge STATIC
    "${porydaw_pluginbridge_dir}/pluginbridge_wait.c"
    "${porydaw_pluginbridge_dir}/pluginbridge.h"
)
set_target_properties(PorydawPluginBridge PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
target_include_directories(PorydawPluginBridge PUBLIC "${porydaw_pluginbridge_dir}")
target_compile_options(PorydawPluginBridge PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${porydaw_pluginbridge_dir}/bridge.modulemap>"
)
target_compile_options(PorydawPluginBridge PRIVATE
    "$<$<COMPILE_LANG_AND_ID:C,MSVC>:/experimental:c11atomics>"
)
if(UNIX AND NOT APPLE)
    target_link_libraries(PorydawPluginBridge PRIVATE rt)
elseif(WIN32)
    target_link_libraries(PorydawPluginBridge PRIVATE kernel32)
endif()

add_library(PorydawPluginHost STATIC
    HelperProcess.swift
    BridgeChannel.swift
    PluginCatalog.swift
    PluginInstance.swift
    PluginEditorShortcuts.swift
    CaptureTransport.swift
    CaptureDriver.swift
    LiveInsert.swift
    LiveTakeRing.swift
    LiveTake.swift
)
set_target_properties(PorydawPluginHost PROPERTIES
    Swift_MODULE_NAME PorydawPluginHost
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
target_include_directories(PorydawPluginHost INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawPluginHost,Swift_MODULE_DIRECTORY>>"
)
target_link_libraries(PorydawPluginHost PUBLIC PorydawCore PorydawPlayback PorydawPluginBridge)
porydaw_enable_swift_batch_mode(PorydawPluginHost)
if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawPluginHost PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()
