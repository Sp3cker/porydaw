cmake_minimum_required(VERSION 3.29)

project(SwiftGridPrototype LANGUAGES CXX Swift)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.10 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    Test
)

include(FetchContent)
FetchContent_Declare(QtBridge
    GIT_REPOSITORY https://github.com/qt/qtbridge-swift.git
    GIT_TAG 407714006dd21107b70db6547ce75e43df0c8a75
)
FetchContent_MakeAvailable(QtBridge)

if(APPLE)
    # Same framework-header precedence fix as the root build: keep Qt's exact
    # framework-header paths ahead of unrelated non-framework Qt installs such
    # as /usr/local/include/Qt*. Treating imported frameworks as system
    # headers lets Clang select the unrelated include tree first.
    foreach(qt_target IN ITEMS Core Gui Qml Quick Test)
        get_target_property(qt_include_dirs Qt6::${qt_target}
            INTERFACE_INCLUDE_DIRECTORIES)
        if(qt_include_dirs)
            set_property(TARGET Qt6::${qt_target} APPEND PROPERTY
                INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${qt_include_dirs}")
        endif()
    endforeach()
endif()


if(APPLE)
    # NO_SYSTEM_FROM_IMPORTED must apply to the upstream targets too; the
    # property is per-target and does not propagate through linking.
    set_target_properties(QtBridgeCpp QtBridge
        PROPERTIES NO_SYSTEM_FROM_IMPORTED ON)
endif()

# Verification-only native smoke driver (event injection; no UI/model logic).
# Kept as a separate static target so Qt6::Test's QT_TESTCASE_* compile
# definitions stay on C++ and never reach the Swift compilation.
set(SWIFT_GRID_SMOKE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../checks/swiftgridprototype"
)

add_library(swift_grid_smoke STATIC
    "${SWIFT_GRID_SMOKE_DIR}/grid_smoke.cpp"
)
target_include_directories(swift_grid_smoke PRIVATE
    "${SWIFT_GRID_SMOKE_DIR}"
)
target_link_libraries(swift_grid_smoke PRIVATE
    Qt6::Quick
    Qt6::Test
)
if(APPLE)
    set_target_properties(swift_grid_smoke PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

file(GLOB SWIFT_GRID_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.swift"
)
file(GLOB SWIFT_GRID_QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

add_executable(swift_grid_prototype
    ${SWIFT_GRID_SOURCES}
)

if(APPLE)
    set_target_properties(swift_grid_prototype PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

target_compile_options(swift_grid_prototype PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-Xcc>"
    "$<$<COMPILE_LANGUAGE:Swift>:-fmodule-map-file=${SWIFT_GRID_SMOKE_DIR}/module.modulemap>"
)

target_link_libraries(swift_grid_prototype PRIVATE
    QtBridge
    Qt6::Quick
    "$<LINK_ONLY:swift_grid_smoke>"
)

set(SWIFT_GRID_FONT_QRC
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../resources/fonts.qrc"
)

set_target_properties(swift_grid_prototype PROPERTIES AUTORCC ON)
target_sources(swift_grid_prototype PRIVATE "${SWIFT_GRID_FONT_QRC}")

if(APPLE)
    set_target_properties(swift_grid_prototype PROPERTIES
        MACOSX_BUNDLE TRUE
    )
    target_sources(swift_grid_prototype PRIVATE ${SWIFT_GRID_QML_FILES})
    set_source_files_properties(${SWIFT_GRID_QML_FILES} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources
    )
else()
    foreach(qml_file IN LISTS SWIFT_GRID_QML_FILES)
        get_filename_component(qml_name "${qml_file}" NAME)
        add_custom_command(
            TARGET swift_grid_prototype POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy
                "${qml_file}"
                "$<TARGET_FILE_DIR:swift_grid_prototype>/${qml_name}"
            COMMENT "Copying ${qml_name} next to executable"
        )
    endforeach()
endif()
