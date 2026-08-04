# Shared macro to avoid duplicating the FetchContent code across the
# per-repo fetch_*.cmake files. Those files (and this one) can be
# included by either the top-level toolchain cmake, or the
# embedded-runtimes/embedded-multilib sub-projects.
# FETCHCONTENT_SOURCE_DIR_<NAME> should be passed down from the
# top level to any library builds to prevent repeated checkouts.

# Capture this file's directory now. CMAKE_CURRENT_LIST_DIR inside
# fetch_repo() below would otherwise resolve to the including file's
# directory.
set(fetch_repo_cmake_dir ${CMAKE_CURRENT_LIST_DIR})

macro(fetch_repo name)
    include(FetchContent)
    include(${fetch_repo_cmake_dir}/patch_repo.cmake)

    if(NOT VERSIONS_JSON)
        include(${fetch_repo_cmake_dir}/read_versions.cmake)
    endif()
    read_repo_version(${name} ${name})
    get_patch_command(${fetch_repo_cmake_dir}/.. ${name} ${name}_patch_command)

    FetchContent_Declare(${name}
        GIT_REPOSITORY "${${name}_URL}"
        GIT_TAG "${${name}_TAG}"
        GIT_SHALLOW "${${name}_SHALLOW}"
        GIT_PROGRESS TRUE
        PATCH_COMMAND ${${name}_patch_command}
        # We only want to download the content, not configure it at this
        # stage.
        SOURCE_SUBDIR do_not_add_${name}_subdir
    )
    FetchContent_MakeAvailable(${name})
    string(TOUPPER ${name} name_upper)
    FetchContent_GetProperties(${name} SOURCE_DIR FETCHCONTENT_SOURCE_DIR_${name_upper})
    unset(name_upper)
endmacro()
