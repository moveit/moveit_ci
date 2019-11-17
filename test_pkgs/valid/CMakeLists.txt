cmake_minimum_required(VERSION 2.8.3)
project(valid)

add_compile_options(-std=c++14)
find_package(catkin REQUIRED)

catkin_package()

include_directories(
  ${catkin_INCLUDE_DIRS}
)

if (CATKIN_ENABLE_TESTING)
  catkin_add_gtest(${PROJECT_NAME} test.cpp)
endif()

# to run: catkin_make -DENABLE_COVERAGE_TESTING=ON package_name_coverage
if(CATKIN_ENABLE_TESTING AND ENABLE_COVERAGE_TESTING)
  find_package(code_coverage REQUIRED)   # catkin package ros-*-code-coverage
  include(CodeCoverage)
  APPEND_COVERAGE_COMPILER_FLAGS()
endif()
