# Check each file independently so earlier fixes remain applied when a checkout
# receives newly added source patches.
foreach(patched_file IN ITEMS
    Sources/QtBridgeMacros/Extensions.swift
    CMakeLists.txt
    Sources/QtBridge/QmlInstantiable.swift
    Sources/QtBridge/QVariant.swift
)
    execute_process(
        COMMAND git apply "--include=${patched_file}" --reverse --check "${PATCH}"
        RESULT_VARIABLE already_applied OUTPUT_QUIET ERROR_QUIET)
    if(NOT already_applied EQUAL 0)
        execute_process(
            COMMAND git apply "--include=${patched_file}" "${PATCH}"
            COMMAND_ERROR_IS_FATAL ANY)
    endif()
endforeach()
