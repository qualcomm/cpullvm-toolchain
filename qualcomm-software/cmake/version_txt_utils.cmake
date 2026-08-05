# Retrieve the correct VERSION.txt name for a given C library.
function(get_version_txt_name clib_name version_txt_name_out)
    if("${clib_name}" STREQUAL picolibc)
        set(${version_txt_name_out} "VERSION.txt" PARENT_SCOPE)
    else()
        set(${version_txt_name_out} "VERSION_${clib_name}.txt" PARENT_SCOPE)
    endif()
endfunction()

# Retrieve the commit for `project_name` out of a VERSIONS.txt-like file
# given by `filename`.
function(get_commit_from_version_txt filename project_name commit_out)
    file(READ "${filename}" contents)
    if(contents MATCHES "\\* ${project_name}:[^\n]*\\(commit ([a-f0-9]+)\\)")
        set(${commit_out} "${CMAKE_MATCH_1}" PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not find commit for '${project_name}' in ${filename}")
    endif()
endfunction()

# Retrieve the url for `project_name` out of a VERSIONS.txt-like file
# given by `filename`.
function(get_url_from_version_txt filename project_name url_out)
    file(READ "${filename}" contents)
    if(contents MATCHES "\\* ${project_name}: ([^ \t\n]+) \\(commit")
        set(${url_out} "${CMAKE_MATCH_1}" PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not find URL for '${project_name}' in ${filename}")
    endif()
endfunction()
