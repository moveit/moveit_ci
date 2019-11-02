# MoveIt Continous Integration
Common Travis CI configuration for MoveIt project

Authors: Robert Haschke, Dave Coleman, Isaac I. Y. Saito

- Uses [pre-build Docker containers](https://hub.docker.com/r/moveit/moveit) for all ROS distros to save setup time
- Simple Travis configuration
- Nicely folded Travis output, tweaked to prevent Travis from bailing out due to oversized log or stalled output
- Allows to pull in additional ROS repositories and build them from source along with the to-be-tested one
- Runs tests on the current repository only, i.e. external packages are not tested
- Builds into install space

[![Build Status](https://travis-ci.org/ros-planning/moveit_ci.svg?branch=master)](https://travis-ci.org/ros-planning/moveit_ci)

## Usage

Create a ``.travis.yml`` file in the base of you repo similar to:

```yaml
# This config file for Travis CI utilizes https://github.com/ros-planning/moveit_ci/ package.
sudo: required
dist: trusty
services:
  - docker
language: cpp
compiler: gcc
cache: ccache

notifications:
  email:
    recipients:
      # - user@email.com
env:
  global: # default values that are common to all configurations (can be overriden below)
    - ROS_DISTRO=melodic   # ROS distro to test for
    - ROS_REPO=ros         # ROS binary repository [ros | ros-shadow-fixed]
    - TEST_BLACKLIST=      # list packages, for which to skip the unittests
    - WARNINGS_OK=false    # Don't accept warnings [true | false]
  matrix:  # define various jobs
    - TEST=clang-format    # check code formatting for compliance to .clang-format rules
    - TEST=clang-tidy-fix  # perform static code analysis and compliance check against .clang-tidy rules
    - TEST=catkin_lint     # perform catkin_lint checks
    - TEST=code-coverage   # perform code coverage report
    # pull in packages from a local .rosinstall file
    - UPSTREAM_WORKSPACE=moveit.rosinstall
    # pull in packages from a remote .rosinstall file and run for a non-default ROS_DISTRO
    - UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/moveit.rosinstall
      ROS_DISTRO=kinetic  ROS_REPO=ros-shadow-fixed

matrix:
  include: # Add a separate config to the matrix, using clang as compiler
    - env: TEST=clang-tidy-check  # run static code analysis, but don't check for available auto-fixes
      compiler: clang
  allow_failures:
    - env: ROS_DISTRO=kinetic  ROS_REPO=ros  UPSTREAM_WORKSPACE=https://github.com/ros-planning/moveit#$ROS_DISTRO-devel

before_script:
  # Clone the moveit_ci repository into Travis' workspace
  - git clone --depth 1 -q https://github.com/ros-planning/moveit_ci.git .moveit_ci

script:
  # Run the test script
  - .moveit_ci/travis.sh
```

## Configurations

- There are essentially two options two specify the underlying ROS docker container to use:
  1. Using the two variables `ROS_DISTRO` and `ROS_REPO`, which automagically choose a suitable [MoveIt docker image](https://hub.docker.com/r/moveit/moveit/tags).
     - `ROS_DISTRO`: (required) determines which version of ROS to use, i.e. kinetic, melodic, ...
     - `ROS_REPO`: (default: ros) determines which ROS package repository to use, either the regular release repo or, specifying `ros-shadow-fixed`, the [shadow prerelease repo](http://wiki.ros.org/ShadowRepository).
  2. Directly specifying `DOCKER_IMAGE`, e.g. `DOCKER_IMAGE=moveit/moveit:master-source`. The docker image may define a `ROS_UNDERLAY` to build the catkin workspace against. By default, this is the root ROS folder in /opt/ros.
- `BEFORE_DOCKER_SCRIPT`: (default: none): Used to specify shell commands or scripts that run before starting the docker container. This is similar to Travis' ``before_script`` section, but the variable allows to dynamically switch scripts within the testing matrix.
- `BEFORE_SCRIPT`: (default: none): Used to specify shell commands or scripts that run in docker, just after setting up the ROS workspace and before actually starting the build processes. In contrast to BEFORE_DOCKER_SCRIPT, this script runs in the context of the docker container.
- `UPSTREAM_WORKSPACE` (default: debian): Configure additional packages for your ROS workspace.
  By default, all dependent packages will be downloaded as binary packages from `$ROS_REPO`.
  Setting this variable to a `http://github.com/user/repo#branch` repository url, will clone the corresponding repository into the workspace.
  Setting this variable to a `http://` url, or a local file in your repository, will merge the corresponding `.rosinstall` file with [`wstool`](http://wiki.ros.org/wstool) into your workspace.
Multiple sources can be given as a comma-, or semicolon-separated lists. Note: their order matters -- if the same resource is defined twice, only the first one is considered.
- `TEST_BLACKLIST`: Allow certain tests to be skipped if necessary (not recommended).
- `TEST`: list of additional tests to perform: clang-format, clang-tidy-check, clang-tidy-fix, catkin\_lint

More configurations as seen in [industrial_ci](https://github.com/ros-industrial/industrial_ci) can be added in the future.

## Removed Configuration

- `CI_PARENT_DIR` renamed to `MOVEIT_CI_DIR`

## Clang-Format

``clang-format`` allows to validate that the source code is properly formatted according to a specification provided in ``.clang-format`` files in the folder hierarchy.
Use ``TEST=clang-format`` to enable this test.

## Clang-Tidy

``clang-tidy`` allows for static code analysis and validation of naming rules.
Use ``TEST=clang-tidy-check`` to enable clang-tidy analysis, but only issuing warnings.
Use ``TEST=clang-tidy-fix`` to reject code that doesn't comply to the rules.

## Catkin Lint

``catkin_lint`` checks for comment issues in your ``package.xml`` and ``CMakeLists`` files.

## `WARNINGS_OK`

The script automatically checks for warnings issued during the build process and provides
a summary in the end. If don't want to accept warnings, and make Travis fail your build in this case, please specify ``WARNINGS_OK=false``.

## Running Locally For Testing

It's also possible to run the moveit\_ci script locally, without Travis. We demonstrate this using MoveIt as the example repository:

First clone the repo you want to test:

    cd /tmp/travis   # any working directory will do
    git clone https://github.com/ros-planning/moveit
    cd moveit

Next clone the CI script:

    git clone https://github.com/ros-planning/moveit_ci .moveit_ci

Manually define the variables, Travis would otherwise define for you. These are required:

    export TRAVIS_BRANCH=melodic-devel
    export ROS_DISTRO=melodic
    export ROS_REPO=ros-shadow-fixed
    export CC=gcc
    export CXX=g++

The rest is optional:

    export UPSTREAM_WORKSPACE=moveit.rosinstall
    export TEST=clang-format

Start the script

    .moveit_ci/travis.sh

It's also possible to run the script without using docker. To this end, issue the following additional commands:

    export IN_DOCKER=1               # pretend running docker
    export CI_SOURCE_PATH=$PWD       # repository location in, i.e. /tmp/travis/moveit
    export ROS_WS=/tmp/ros_ws        # define a new ROS workspace location
    mkdir $ROS_WS                    # and create it
    .moveit_ci/travis.sh

## Enabling codecov.io reporting

For codecov to work you need to build and link your c++ code with the `--coverage` flag.  We do this with a custom `Coverage` build type for cmake.  To add support for Coverage build type add this [Coverage.cmake](https://raw.githubusercontent.com/Lectem/cpp-boilerplate/master/cmake/Coverage.cmake) file from the [cpp-boilerplate](https://github.com/Lectem/cpp-boilerplate/blob/master/CTestConfig.cmake) project to a `cmake` directory.  Then update the minimum required version of cmake to `3.3` or higher to support features from that file:

    cmake_minimum_required(VERSION 3.3)

Add These lines to your cmake file to include `Coverage`:

    # Custom modules and scripts
    set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_CURRENT_LIST_DIR}/cmake")
    include(Coverage)

Lastly, Add a `.codecov.yml` file to your project to exclude test, external, main files, and anything else you don't want in your coverage report:

    ignore:
      - "test"          # test directory
      - "external"      # external directory
      - "**/*_main.cpp" # any file ending in _main.cpp

Then you can use the `code-coverage` test and it will run the script provided by [codecov.io](codecov.io) which runs `gcov` to generate the reports and then compiles them into a report and uploads them to their servers.

If you are using this on a private github repo you will need to define the `CODECOV_TOKEN` enviroment variable in the `global` section of your `.travis.yml` file to the value you can find on the settings page of your project on codecov.io.
