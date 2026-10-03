include_guard(GLOBAL)

include(FetchContent)
FetchContent_Declare(BinaryParsingSource
    GIT_REPOSITORY https://github.com/apple/swift-binary-parsing.git
    GIT_TAG 2655f40f579c686d44687ac4fed54c73c3c4be2e
)
FetchContent_Populate(BinaryParsingSource)

file(GLOB_RECURSE binary_parsing_sources CONFIGURE_DEPENDS
    "${binaryparsingsource_SOURCE_DIR}/Sources/BinaryParsing/*.swift")
# The public magicNumber macro needs a SwiftSyntax plugin; the parser does not use it.
list(REMOVE_ITEM binary_parsing_sources
    "${binaryparsingsource_SOURCE_DIR}/Sources/BinaryParsing/Macros/Macros.swift")
add_library(BinaryParsing STATIC ${binary_parsing_sources})
set_target_properties(BinaryParsing PROPERTIES
    Swift_MODULE_NAME BinaryParsing
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/binary-parsing-module"
    Swift_LANGUAGE_VERSION 6
)
target_compile_options(BinaryParsing PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
    "$<$<COMPILE_LANGUAGE:Swift>:-strict-memory-safety>"
)
target_include_directories(BinaryParsing INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:BinaryParsing,Swift_MODULE_DIRECTORY>>"
)
