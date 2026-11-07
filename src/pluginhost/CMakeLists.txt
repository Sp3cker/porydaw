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

if(APPLE)
    enable_language(OBJCXX)
    target_sources(porydaw_vst3_sdk PRIVATE
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_mac.mm")
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
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_win32.cpp")
    target_link_libraries(porydaw_vst3_sdk PRIVATE ole32 shell32)
else()
    find_package(Threads REQUIRED)
    target_sources(porydaw_vst3_sdk PRIVATE
        "${porydaw_vst3_sdk_root}/public.sdk/source/vst/hosting/module_linux.cpp")
    target_link_libraries(porydaw_vst3_sdk PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
endif()
