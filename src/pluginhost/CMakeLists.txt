set(porydaw_vst3_sdk_root "${PROJECT_SOURCE_DIR}/external/vst3sdk")

# Mirror the pinned SMTG_VST3_SDK.cmake base, pluginterfaces and hosting targets.
add_library(porydaw_vst3_sdk STATIC
    "${porydaw_vst3_sdk_root}/base/source/baseiids.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fbuffer.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fdebug.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fdynlib.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fobject.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fstreamer.cpp"
    "${porydaw_vst3_sdk_root}/base/source/fstring.cpp"
    "${porydaw_vst3_sdk_root}/base/source/timer.cpp"
    "${porydaw_vst3_sdk_root}/base/source/updatehandler.cpp"
    "${porydaw_vst3_sdk_root}/base/thread/source/fcondition.cpp"
    "${porydaw_vst3_sdk_root}/base/thread/source/flock.cpp"
    "${porydaw_vst3_sdk_root}/pluginterfaces/base/conststringtable.cpp"
    "${porydaw_vst3_sdk_root}/pluginterfaces/base/coreiids.cpp"
    "${porydaw_vst3_sdk_root}/pluginterfaces/base/funknown.cpp"
    "${porydaw_vst3_sdk_root}/pluginterfaces/base/ustring.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/connectionproxy.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/eventlist.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/hostclasses.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/parameterchanges.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/processdata.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/plugprovider.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/vstinitiids.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/common/memorystream.cpp"
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/utility/stringconvert.cpp"
    # smtg_create_public_sdk_hosting_target: HostApplication uses PlugInterfaceSupport.
    "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/pluginterfacesupport.cpp"
    # smtg_create_public_sdk_hosting_target links sdk_common; stringconvert calls this.
    "${porydaw_vst3_sdk_root}/public.sdk/source/common/commonstringconvert.cpp"
    # smtg_create_public_sdk_hosting_target links sdk_common, which supplies view IIDs.
    "${porydaw_vst3_sdk_root}/public.sdk/source/common/commoniids.cpp"
)
set_target_properties(porydaw_vst3_sdk PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
# Only native helper/check targets consume this SDK; never add it to Swift modules.
target_include_directories(porydaw_vst3_sdk SYSTEM PUBLIC "${porydaw_vst3_sdk_root}")
target_compile_definitions(porydaw_vst3_sdk PUBLIC
    "$<$<CONFIG:Debug>:DEVELOPMENT=1>"
    "$<$<NOT:$<CONFIG:Debug>>:RELEASE=1;NDEBUG>"
)

# smtg_create_public_sdk_hosting_target links sdk_common; its platform ThreadChecker
# implementation backs ConnectionProxy's thread checks.
if(APPLE)
    enable_language(OBJCXX)
    target_sources(porydaw_vst3_sdk PRIVATE
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_mac.mm"
        "${porydaw_vst3_sdk_root}/public.sdk/source/common/threadchecker_mac.mm")
    set_source_files_properties(
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_mac.mm"
        PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
    set_target_properties(porydaw_vst3_sdk PROPERTIES
        OBJCXX_STANDARD 17
        OBJCXX_STANDARD_REQUIRED ON
        OBJCXX_EXTENSIONS OFF)
    target_link_libraries(porydaw_vst3_sdk PRIVATE
        "-framework Cocoa"
        "-framework CoreFoundation")
elseif(WIN32)
    target_sources(porydaw_vst3_sdk PRIVATE
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_win32.cpp"
        "${porydaw_vst3_sdk_root}/public.sdk/source/common/threadchecker_win32.cpp")
    target_link_libraries(porydaw_vst3_sdk PRIVATE ole32 shell32)
else()
    find_package(Threads REQUIRED)
    target_sources(porydaw_vst3_sdk PRIVATE
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_linux.cpp"
        "${porydaw_vst3_sdk_root}/public.sdk/source/common/threadchecker_linux.cpp")
    target_link_libraries(porydaw_vst3_sdk PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
endif()

set_target_properties(porydaw_vst3_sdk PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(porydaw_pluginhost STATIC
    pluginhost.h pluginhost_internal.h pluginhost.cpp pluginhost_process.cpp)
set_target_properties(porydaw_pluginhost PROPERTIES
    CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
target_include_directories(porydaw_pluginhost PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(porydaw_pluginhost PRIVATE porydaw_vst3_sdk)

add_executable(porydaw-vst3-host scanner/scanner_main.cpp)
set_target_properties(porydaw-vst3-host PROPERTIES
    CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
target_link_libraries(porydaw-vst3-host PRIVATE porydaw_pluginhost)
if(APPLE)
    add_custom_command(TARGET porydaw-vst3-host POST_BUILD
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "$<TARGET_BUNDLE_CONTENT_DIR:porydaw>/MacOS"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "$<TARGET_FILE:porydaw-vst3-host>"
            "$<TARGET_BUNDLE_CONTENT_DIR:porydaw>/MacOS/porydaw-vst3-host"
        VERBATIM)
elseif(WIN32)
    set_target_properties(porydaw-vst3-host PROPERTIES WIN32_EXECUTABLE TRUE)
    target_link_libraries(porydaw-vst3-host PRIVATE shell32)
    install(TARGETS porydaw-vst3-host RUNTIME DESTINATION .)
endif()
