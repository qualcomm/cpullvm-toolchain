// RUN: %clangxx %{target-arm} -fno-exceptions -fno-rtti %{link-semihost} %s -o %t-arm.elf
// RUN: %if qemu-arm %{ %{qemu-arm} %t-arm.elf 2>&1 | FileCheck %s %}
// RUN: %clangxx %{target-aarch64} -fno-exceptions -fno-rtti %{link-semihost} %s -o %t-aarch64.elf
// RUN: %if qemu-aarch64 %{ %{qemu-aarch64} %t-aarch64.elf 2>&1 | FileCheck %s %}
// RUN: %clangxx %{target-riscv32} -fno-exceptions -fno-rtti %{link-semihost} %s -o %t-riscv32.elf
// RUN: %if qemu-riscv32 %{ %{qemu-riscv32} %t-riscv32.elf 2>&1 | FileCheck %s %}
// RUN: %clangxx %{target-riscv32-xqci} -fno-exceptions -fno-rtti %{link-semihost} %s -o %t-riscv32-xqci.elf
// RUN: %if qemu-riscv32-xqci %{ %{qemu-riscv32-xqci} %t-riscv32-xqci.elf 2>&1 | FileCheck %s %}
// RUN: %clangxx %{target-riscv64} -fno-exceptions -fno-rtti %{link-semihost} %s -o %t-riscv64.elf
// RUN: %if qemu-riscv64 %{ %{qemu-riscv64} %t-riscv64.elf 2>&1 | FileCheck %s %}

// Include as many C++17 headers as possible.
// Unsupported headers are commented out.
#include <algorithm>
#include <any>
#include <array>
#include <atomic>
#include <bitset>
#include <chrono>
#include <codecvt>
#include <complex>
#include <condition_variable>
#include <deque>
#include <exception>
#include <execution>
//#include <filesystem>
#include <forward_list>
#include <fstream>
#include <functional>
//#include <future>
#include <initializer_list>
#include <iomanip>
#include <ios>
#include <iosfwd>
#include <iostream>
#include <istream>
#include <iterator>
#include <limits>
#include <list>
#include <locale>
#include <map>
#include <memory>
#include <memory_resource>
//#include <mutex>
#include <new>
#include <numeric>
#include <optional>
#include <ostream>
#include <queue>
#include <random>
#include <ratio>
#include <regex>
#include <scoped_allocator>
#include <set>
//#include <shared_mutex>
#include <sstream>
#include <stack>
#include <stdexcept>
#include <streambuf>
#include <string>
#include <string_view>
#include <strstream>
#include <system_error>
//#include <thread>
#include <tuple>
#include <type_traits>
#include <typeindex>
#include <typeinfo>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <valarray>
#include <variant>
#include <vector>

#include <cassert>
#include <cinttypes>
#include <csignal>
#include <cstdio>
//#include <cwchar>
#include <ccomplex>
#include <ciso646>
//#include <cstdalign> // removed in C++20
#include <cstdlib>
//#include <cwctype>
#include <cctype>
#include <climits>
#include <cstdarg>
#include <cstring>
#include <cerrno>
#include <clocale>
#include <cstdbool>
#include <ctgmath>
#include <cfenv>
#include <cmath>
#include <cstddef>
#include <ctime>
#include <cfloat>
#include <csetjmp>
#include <cstdint>
#include <cuchar>

int main(void) {
    std::string str = "Hello World!";
    std::cout << str << std::endl; // CHECK: Hello World!
    return 0;
}
