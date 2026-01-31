# To avoid duplicating the FetchContent code, this file can be
# included by either the top-level toolchain cmake, or the
# runtimes sub-project.
# FETCHCONTENT_SOURCE_DIR_MUSL should be passed down from the
# top level to any library builds to prevent repeated checkouts.

include(FetchContent)
include(${CMAKE_CURRENT_LIST_DIR}/patch_repo.cmake)

if(NOT VERSIONS_JSON)
    include(${CMAKE_CURRENT_LIST_DIR}/read_versions.cmake)
endif()
read_repo_version(musl musl)
get_patch_command(${CMAKE_CURRENT_LIST_DIR}/.. musl musl_patch_command)

FetchContent_Declare(musl
    GIT_REPOSITORY "${musl_URL}"
    GIT_TAG "${musl_TAG}"
    GIT_SHALLOW "${musl_SHALLOW}"
    GIT_PROGRESS TRUE
    PATCH_COMMAND ${musl_patch_command}
    # We only want to download the content, not configure it at this
    # stage. musl will be built in many configurations using
    # ExternalProject_Add using the sources that are checked out here.
    SOURCE_SUBDIR do_not_add_musl_subdir
)
FetchContent_MakeAvailable(musl)
FetchContent_GetProperties(musl SOURCE_DIR FETCHCONTENT_SOURCE_DIR_MUSL)
