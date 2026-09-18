# Check each file independently so a checkout with the earlier object-return
# fixes can receive the registration access change without reapplying them.
foreach(patched_file IN ITEMS
    Sources/QtBridgeMacros/Extensions.swift
    CMakeLists.txt
    Sources/QtBridge/QmlInstantiable.swift
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
