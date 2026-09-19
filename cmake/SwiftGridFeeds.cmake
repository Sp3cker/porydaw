include_guard(GLOBAL)

# Shared Swift-grid seam closure: the feed sources compiled by BOTH the
# production app target and the standalone prototype lane, plus the include
# roots every feed TU needs. Lane-specific TUs (session_feed_view,
# swift_grid_document_feed, swift_roll_mount) stay with the target that owns
# their symbols. Edit this file only — never re-spell the set per lane.
# PORYAAAA_DIR must already be set by the including build.
add_library(swift_grid_feed_closure INTERFACE)
target_sources(swift_grid_feed_closure INTERFACE
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/document_feed.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/document_feed.h"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/command_feed.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/command_feed.h"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/intent_executor.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/intent_executor.h"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/session_feed.cpp"
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid/session_feed.h"
)
target_include_directories(swift_grid_feed_closure INTERFACE
    "${CMAKE_CURRENT_LIST_DIR}/../src/ui/songview/quick/swiftgrid"
    "${CMAKE_CURRENT_LIST_DIR}/../src"
)
target_include_directories(swift_grid_feed_closure SYSTEM INTERFACE
    "${PORYAAAA_DIR}/third_party"
    "${PORYAAAA_DIR}/plugin/porydaw/.."
    "${PORYAAAA_DIR}/plugin/m4a"
    "${PORYAAAA_DIR}/plugin/hw_audio/.."
)
target_link_libraries(swift_grid_feed_closure INTERFACE Qt6::Core Qt6::Widgets)
