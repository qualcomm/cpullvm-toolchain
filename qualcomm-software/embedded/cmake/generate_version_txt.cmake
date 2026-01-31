# The following line will look different depending on how you got this
# source file. If you got it from a Git repository then it will contain
# a string in the git pretty format with dollar symbols. If you got it
# from a source archive then the `git archive` command should have
# replaced the format string with the Git revision at the time the
# archive was created. This is configured in the .gitattributes file.
# In the former case, this script will run a Git command to find out the
# current revision. In the latter case the revision will be used as is.
set(cpullvm_COMMIT "$Format:%H$")

if(NOT ${cpullvm_COMMIT} MATCHES "^[a-f0-9]+$")
    execute_process(
        COMMAND git -C ${CPULLVMToolchain_SOURCE_DIR} rev-parse HEAD
        OUTPUT_VARIABLE cpullvm_COMMIT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )
endif()

execute_process(
    COMMAND git -C ${eld_SOURCE_DIR} rev-parse HEAD
    OUTPUT_VARIABLE eld_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    COMMAND_ERROR_IS_FATAL ANY
)

# Supported libcs are all in a separate repo
set(base_library ${LLVM_TOOLCHAIN_C_LIBRARY})

execute_process(
    COMMAND git -C ${${base_library}_SOURCE_DIR} rev-parse HEAD
    OUTPUT_VARIABLE ${base_library}_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE 
    COMMAND_ERROR_IS_FATAL ANY
)
set(LLVM_TOOLCHAIN_C_LIBRARY_URL ${${base_library}_URL})
set(LLVM_TOOLCHAIN_C_LIBRARY_COMMIT ${${base_library}_COMMIT})

configure_file(
    ${CMAKE_CURRENT_LIST_DIR}/VERSION.txt.in
    ${CMAKE_CURRENT_BINARY_DIR}/VERSION.txt
)
