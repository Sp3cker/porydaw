set(fixture_sdk "${PROJECT_SOURCE_DIR}/external/vst3sdk")
set(fixture_plugin_sources
    # smtg_create_public_sdk_target supplies CPluginView for vsteditcontroller.cpp.
    "${fixture_sdk}/public.sdk/source/common/pluginview.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstsinglecomponenteffect.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstbus.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstcomponent.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstcomponentbase.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vsteditcontroller.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstparameters.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstaudioeffect.cpp"
    "${fixture_sdk}/public.sdk/source/vst/vstinitiids.cpp"
    "${fixture_sdk}/public.sdk/source/main/pluginfactory.cpp")
if(APPLE)
    set(fixture_platform_main "${fixture_sdk}/public.sdk/source/main/macmain.cpp")
elseif(WIN32)
    set(fixture_platform_main "${fixture_sdk}/public.sdk/source/main/dllmain.cpp")
else()
    set(fixture_platform_main "${fixture_sdk}/public.sdk/source/main/linuxmain.cpp")
endif()

foreach(fixture IN ITEMS porydawtestgen porydawtestcrash porydawtesthang)
    add_library(${fixture} MODULE
        "${fixture}.cpp"
        "${fixture_sdk}/public.sdk/source/main/moduleinit.cpp"
        "${fixture_platform_main}")
    set_target_properties(${fixture} PROPERTIES
        CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON CXX_EXTENSIONS OFF
        AUTOMOC OFF AUTOUIC OFF AUTORCC OFF INTERPROCEDURAL_OPTIMIZATION OFF
        INTERPROCEDURAL_OPTIMIZATION_RELEASE OFF
        PREFIX "")
    target_link_libraries(${fixture} PRIVATE porydaw_vst3_sdk)
    set(fixture_root "$<TARGET_FILE_DIR:porydaw_checks>/vstfixtures")
    if(APPLE)
        set_target_properties(${fixture} PROPERTIES BUNDLE TRUE BUNDLE_EXTENSION vst3
            SUFFIX "" LIBRARY_OUTPUT_DIRECTORY "${fixture_root}")
        file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${fixture}-Info.plist" CONTENT
"<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<plist version=\"1.0\"><dict>
<key>CFBundleExecutable</key><string>${fixture}</string>
<key>CFBundleIdentifier</key><string>org.porydaw.${fixture}</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1.0.0</string>
</dict></plist>
")
        add_custom_command(TARGET ${fixture} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                "${CMAKE_CURRENT_BINARY_DIR}/${fixture}-Info.plist"
                "$<TARGET_BUNDLE_CONTENT_DIR:${fixture}>/Info.plist"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${PROJECT_BINARY_DIR}/vstfixtures"
            COMMAND "${CMAKE_COMMAND}" -E copy_directory
                "$<TARGET_BUNDLE_DIR:${fixture}>"
                "${PROJECT_BINARY_DIR}/vstfixtures/${fixture}.vst3"
            VERBATIM)
    else()
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
            set(fixture_arch arm64)
        else()
            set(fixture_arch x86_64)
        endif()
        if(WIN32)
            set(fixture_platform "${fixture_arch}-win")
            set_target_properties(${fixture} PROPERTIES SUFFIX ".vst3")
        else()
            if(fixture_arch STREQUAL "arm64")
                set(fixture_arch aarch64)
            endif()
            set(fixture_platform "${fixture_arch}-linux")
        endif()
        set_target_properties(${fixture} PROPERTIES
            LIBRARY_OUTPUT_DIRECTORY "${fixture_root}/${fixture}.vst3/Contents/${fixture_platform}")
    endif()
endforeach()
target_sources(porydawtestgen PRIVATE ${fixture_plugin_sources})
target_compile_definitions(porydawtestgen PRIVATE PROJECT_INCLUDES_VSTEDITCONTROLLER=1)
if(APPLE)
    target_sources(porydawtestgen PRIVATE porydawtestgen_view_mac.mm)
    set_source_files_properties(porydawtestgen_view_mac.mm PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
    set_target_properties(porydawtestgen PROPERTIES OBJCXX_STANDARD 17 OBJCXX_STANDARD_REQUIRED ON)
    target_link_libraries(porydawtestgen PRIVATE "-framework Cocoa")
elseif(WIN32)
    target_sources(porydawtestgen PRIVATE porydawtestgen_view_win.cpp)
    target_link_libraries(porydawtestgen PRIVATE user32 gdi32)
else()
    target_sources(porydawtestgen PRIVATE porydawtestgen_view_x11.cpp)
    target_link_libraries(porydawtestgen PRIVATE PkgConfig::PORYDAW_XCB)
endif()
