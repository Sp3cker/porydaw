# The patch is the single source of truth for which files to patch: derive
# the list from its own diff headers instead of hand-mirroring them here.
file(STRINGS "${PATCH}" qtbridge_diff_headers REGEX "^diff --git ")
set(qtbridge_patched_files "")
foreach(qtbridge_header IN LISTS qtbridge_diff_headers)
    string(REGEX REPLACE "^diff --git a/([^ ]+) b/.*$" "\\1" qtbridge_file
        "${qtbridge_header}")
    list(APPEND qtbridge_patched_files "${qtbridge_file}")
endforeach()

# Check each file independently so earlier fixes remain applied when a checkout
# receives newly added source patches.
foreach(patched_file IN ITEMS ${qtbridge_patched_files})
    execute_process(
        COMMAND git apply "--include=${patched_file}" --reverse --check "${PATCH}"
        RESULT_VARIABLE already_applied OUTPUT_QUIET ERROR_QUIET)
    if(NOT already_applied EQUAL 0)
        execute_process(
            COMMAND git apply "--include=${patched_file}" "${PATCH}"
            COMMAND_ERROR_IS_FATAL ANY)
    endif()
endforeach()
