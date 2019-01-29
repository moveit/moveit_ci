# MoveIt Continous Integration
Common Travis CI configuration for MoveIt! project

Authors: Dave Coleman, Isaac I. Y. Saito, Robert Haschke

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

- `ROS_DISTRO`: (required) which version of ROS, i.e. kinetic, melodic, ...
- `ROS_REPO`: (default: ros) install ROS debians from either regular release or from [shadow-fixed](http://packages.ros.org/ros-shadow-fixed/ubuntu)
- `BEFORE_DOCKER_SCRIPT`: (default: none): Used to specify shell commands or scripts that run before starting the docker container. This is similar to Travis' ``before_script`` section, but the variable allows to dynamically switch scripts within the testing matrix.
- `BEFORE_SCRIPT`: (default: none): Used to specify shell commands or scripts that run in docker, just after setting up the catkin workspace and before actually starting the build processes. In contrast to BEFORE_DOCKER_SCRIPT, this script runs in the context of the docker container.
- `UPSTREAM_WORKSPACE` (default: debian): Configure additional packages for your catkin workspace.
  By default, all dependent packages will be downloaded as binary packages from `$ROS_REPO`.
  Setting this variable to a `http://github.com/user/repo#branch` repository url, will clone the corresponding repository into the workspace.
  Setting this variable to a `http://` url, or a local file in your repository, will merge the corresponding `.rosinstall` file with [`wstool`](http://wiki.ros.org/wstool) into your workspace.
When set as "file", the dependended packages that need to be built from source are downloaded based on a .rosinstall file in your repository. Multiple sources can be given as a comma-, or semicolon-separated lists. Note: their order matters -- if the same resource is defined twice, only the first one is considered.
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

It's also possible to run the moveit\_ci script locally, without Travis. We demonstrate this using MoveIt! as the example repository:

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

The rest is optional:

    export UPSTREAM_WORKSPACE=moveit.rosinstall
    export TEST=clang-format

Start the script

    .moveit_ci/travis.sh

It's also possible to run the script without using docker. To this end, issue the following additional commands:

    export IN_DOCKER=1               # pretend running docker
    export CI_SOURCE_PATH=$PWD       # repository location in, i.e. /tmp/travis/moveit
    export CATKIN_WS=/tmp/catkin_ws  # define a new catkin workspace location
    mkdir $CATKIN_WS                 # and create it
    .moveit_ci/travis.sh
