cmake_minimum_required(VERSION 2.8.3)
project(valid)

add_compile_options(-std=c++14)
find_package(catkin REQUIRED)

catkin_package()

include_directories(
  ${catkin_INCLUDE_DIRS}
)

if (CATKIN_ENABLE_TESTING)
  find_package(code_coverage REQUIRED)

  if(ENABLE_COVERAGE_TESTING)
    include(CodeCoverage)
    APPEND_COVERAGE_COMPILER_FLAGS()
  endif()

  catkin_add_gtest(${PROJECT_NAME} test.cpp)
endif()
