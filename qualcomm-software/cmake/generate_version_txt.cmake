# The following line will look different depending on how you got this
# source file. If you got it from a Git repository then it will contain
# a string in the git pretty format with dollar symbols. If you got it
# from a source archive then the `git archive` command should have
# replaced the format string with the Git revision at the time the
# archive was created. This is configured in the .gitattributes file.
# In the former case, this script will run a Git command to find out the
# current revision. In the latter case the revision will be used as is.
set(cpullvm_COMMIT "$Format:%H$")

function(get_commit_from_dir source_dir commit)
    execute_process(
        COMMAND git -C ${source_dir} rev-parse HEAD
        OUTPUT_VARIABLE temp_commit
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )
    set(${commit} ${temp_commit} PARENT_SCOPE)
endfunction()

function(get_commit_for_libc_repo name commit)
    if(PREBUILT_TARGET_LIBRARIES)
        include(${CMAKE_CURRENT_LIST_DIR}/version_txt_utils.cmake)
        get_version_txt_name(${LLVM_TOOLCHAIN_C_LIBRARY} version_txt_name)
        get_commit_from_version_txt(
            "${PREBUILT_TARGET_LIBRARIES_INFO_DIR}/${version_txt_name}"
            ${name}
            temp_commit
        )
    else()
        get_commit_from_dir("${${name}_SOURCE_DIR}" temp_commit)
    endif()
    set(${commit} ${temp_commit} PARENT_SCOPE)
endfunction()

if(NOT ${cpullvm_COMMIT} MATCHES "^[a-f0-9]+$")
    get_commit_from_dir("${CPULLVMToolchain_SOURCE_DIR}" cpullvm_COMMIT)
endif()

get_commit_from_dir("${eld_SOURCE_DIR}" eld_COMMIT)

if(ENABLE_LINUX_LIBRARIES)
    get_commit_for_libc_repo("musl" musl_COMMIT)
    set(musl_version_string "* musl: ${musl_URL} (commit ${musl_COMMIT})\n")

    if(NOT LLVM_TOOLCHAIN_C_LIBRARY STREQUAL musl-embedded)
        get_commit_for_libc_repo("musl-embedded" musl-embedded_COMMIT)
        set(musl-embedded_version_string "* musl-embedded: ${musl-embedded_URL} (commit ${musl-embedded_COMMIT})\n")
    endif()
endif()

# Supported libcs are all in a separate repo
set(base_library ${LLVM_TOOLCHAIN_C_LIBRARY})

get_commit_for_libc_repo("${base_library}" ${base_library}_COMMIT)

set(LLVM_TOOLCHAIN_C_LIBRARY_URL ${${base_library}_URL})
set(LLVM_TOOLCHAIN_C_LIBRARY_COMMIT ${${base_library}_COMMIT})

configure_file(
    ${CMAKE_CURRENT_LIST_DIR}/VERSION.txt.in
    ${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt
)
