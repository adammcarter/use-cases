cmake_minimum_required(VERSION 3.20)
project(ringbuf C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_library(ringbuf src/ringbuf.c)
target_include_directories(ringbuf PUBLIC include)
if(MSVC)
  target_compile_options(ringbuf PRIVATE /W4)
else()
  target_compile_options(ringbuf PRIVATE -Wall -Wextra -Werror)
endif()

enable_testing()
add_executable(ringbuf_tests tests/test_ringbuf.c)
target_link_libraries(ringbuf_tests PRIVATE ringbuf)

foreach(name IN ITEMS starts_empty push_then_pop wraps_around rejects_push_when_full overwrite_mode_drops_oldest peek_does_not_remove)
  add_test(NAME ${name} COMMAND ringbuf_tests ${name})
endforeach()
