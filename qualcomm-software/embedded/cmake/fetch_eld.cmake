# To avoid duplicating the FetchContent code, this file can be
# included by either the top-level toolchain cmake, or the
# embedded-runtimes sub-project.
# FETCHCONTENT_SOURCE_DIR_ELD should be passed down from the
# top level to any library builss to prevent repeated checkouts.

include(FetchContent)
include(${CMAKE_CURRENT_LIST_DIR}/patch_repo.cmake)

if(NOT VERSIONS_JSON)
    include(${CMAKE_CURRENT_LIST_DIR}/read_versions.cmake)
endif()
read_repo_version(eld eld)
get_patch_command(${CMAKE_CURRENT_LIST_DIR}/.. eld eld_patch_command)

FetchContent_Declare(eld
    GIT_REPOSITORY "${eld_URL}"
    GIT_TAG "${eld_TAG}"
    GIT_SHALLOW "${eld_SHALLOW}"
    GIT_PROGRESS TRUE
    PATCH_COMMAND ${eld_patch_command}
    # We only want to download the content, not configure it at this
    # stage. eld will be built as part of LLVM using the sources checked
    # out here.
    SOURCE_SUBDIR do_not_add_eld_subdir
)
FetchContent_MakeAvailable(eld)
FetchContent_GetProperties(eld SOURCE_DIR FETCHCONTENT_SOURCE_DIR_ELD)
