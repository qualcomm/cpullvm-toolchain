# Retrieve the canonical `-march` string given a set of valid compiler flags.
# 
# We require the following arguments:
# - `compiler_path` is expected to contain the path to the compiler to use.
# - `build_args` is expected to be a CMake list (';' separated) of the compiler
#   commands to use (typically `--target=`, `-march=`, etc.). These arguments
#   are expected to all be valid and be sufficient to determine the correct set
#   of extensions.
# - `march_out` should contain the variable to be used to return the
#   canonicalized arch string.
function(get_canonical_riscv_march compiler_path build_args march_out)
    set(command_args ${build_args} "--print-enabled-extensions")
    execute_process(
        COMMAND ${compiler_path}
        ${command_args}
        RESULT_VARIABLE return_val
        OUTPUT_VARIABLE extension_output
        ERROR_VARIABLE extension_output
    )
    if(NOT return_val EQUAL 0)
        message(FATAL_ERROR "Unable to execute `--print-enabled-extensions` to retreive canonical `-march` string")
    endif()
    string(REGEX MATCH
            "ISA String: ([A-Za-z0-9_]+)" out_var "${extension_output}")
    set(${march_out} ${CMAKE_MATCH_1} PARENT_SCOPE)
endfunction()
