# MoveIt Continous Integration
Common Travis CI configuration for MoveIt project

Authors: Robert Haschke, Dave Coleman, Isaac I. Y. Saito

- Uses [pre-build Docker containers](https://hub.docker.com/r/moveit/moveit2) for all ROS distros to save setup time
- Simple Travis configuration
- Nicely folded Travis output, tweaked to prevent Travis from bailing out due to oversized log or stalled output
- Allows to pull in additional ROS repositories and build them from source along with the to-be-tested one
- Runs tests on the current repository only, i.e. external packages are not tested
- Builds into install space

[![Build Status](https://travis-ci.org/ros-planning/moveit_ci.svg?branch=ros2)](https://travis-ci.org/ros-planning/moveit_ci)

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
    - ROS_DISTRO=eloquent   # ROS distro to test for
    - ROS_REPO=ros         # ROS binary repository [ros | ros-shadow-fixed]
    - TEST_BLACKLIST=      # list packages, for which to skip the unittests
    - WARNINGS_OK=false    # Don't accept warnings [true | false]
  matrix:  # define various jobs
    - TEST=clang-format    # check code formatting for compliance to .clang-format rules
    - TEST=clang-tidy-fix  # perform static code analysis and compliance check against .clang-tidy rules
    - TEST=ament_lint      # perform ament_lint checks
    # pull in packages from a local .repos file
    - UPSTREAM_WORKSPACE=moveit2.repos
    # pull in packages from a remote .repos file and run for a non-default ROS_DISTRO
    - UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit2/main/moveit2.repos
      ROS_DISTRO=eloquent

matrix:
  include: # Add a separate config to the matrix, using clang as compiler
    - env: TEST=clang-tidy-check  # run static code analysis, but don't check for available auto-fixes
      compiler: clang
  allow_failures:
    - env: ROS_DISTRO=eloquent  ROS_REPO=ros  UPSTREAM_WORKSPACE=https://github.com/ros-planning/moveit2#main

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
     - `ROS_DISTRO`: (required) determines which version of ROS to use, i.e. eloquent, foxy, ...
     - `ROS_REPO`: (default: ros) determines which ROS package repository to use, either the regular release repo or, specifying `ros-shadow-fixed`, the [shadow prerelease repo](http://wiki.ros.org/ShadowRepository).
  2. Directly specifying `DOCKER_IMAGE`, e.g. `DOCKER_IMAGE=moveit/moveit2:eloquent-ci`. The docker image may define a `ROS_UNDERLAY` to build the catkin workspace against. By default, this is the root ROS folder in /opt/ros.
- `BEFORE_DOCKER_SCRIPT`: (default: none): Used to specify shell commands or scripts that run before starting the docker container. This is similar to Travis' ``before_script`` section, but the variable allows to dynamically switch scripts within the testing matrix.
- `BEFORE_SCRIPT`: (default: none): Used to specify shell commands or scripts that run in docker, just after setting up the ROS workspace and before actually starting the build processes. In contrast to BEFORE_DOCKER_SCRIPT, this script runs in the context of the docker container.
- `UPSTREAM_WORKSPACE` (default: debian): Configure additional packages for your ROS workspace.
  By default, all dependent packages will be downloaded as binary packages from `$ROS_REPO`.
  Setting this variable to a `http://github.com/user/repo#branch` repository url, will clone the corresponding repository into the workspace.
  Setting this variable to a `http://` url, or a local file in your repository, will merge the corresponding `.rosinstall` or `.repos` file with [`vcstool`](https://github.com/dirk-thomas/vcstool) into your workspace.
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

## Ament lint

``ament_lint`` checks for comment issues in your ``package.xml`` and ``CMakeLists`` files.

## `WARNINGS_OK`

The script automatically checks for warnings issued during the build process and provides
a summary in the end. If don't want to accept warnings, and make Travis fail your build in this case, please specify ``WARNINGS_OK=false``.

## Running Locally For Testing

It's also possible to run the moveit\_ci script locally, without Travis. We demonstrate this using MoveIt as the example repository:

First clone the repo you want to test:

    cd /tmp/travis   # any working directory will do
    git clone https://github.com/ros-planning/moveit2
    cd moveit2

Next clone the CI script:

    git clone -b ros2 https://github.com/ros-planning/moveit_ci .moveit_ci

Manually define the variables, Travis would otherwise define for you. These are required:

    export TRAVIS_BRANCH=main   # The base branch to compare changes with (e.g. for clang-tidy)
    export ROS_DISTRO=eloquent
    export ROS_REPO=ros
    export CC=gcc            # The compiler you have chosen in your .travis.yaml
    export CXX=g++

The rest is optional:

    # Export all other environment variables you usually set in your .travis.yaml
    export UPSTREAM_WORKSPACE=moveit2.repos
    export TEST=clang-format

Start the script

    .moveit_ci/travis.sh

It's also possible to run the script without using docker. To this end, issue the following additional commands:

    export IN_DOCKER=1               # pretend running docker
    export CI_SOURCE_PATH=$PWD       # repository location in, i.e. /tmp/travis/moveit
    export ROS_WS=/tmp/ros_ws        # define a new ROS workspace location
    mkdir $ROS_WS                    # and create it

    .moveit_ci/travis.sh

The `travis.sh` script will need to run apt-get as root. To allow this, create a proxy script for `apt-get` in your `PATH`:
1. Create the file ~/.local/bin/apt-get
2. Insert the following text
    ```
    #!/bin/bash
    echo "running apt-get proxy"
    sudo /usr/bin/apt-get "$@"
    ```
3. Make it executable `chmod +x ~/.local/bin/apt-get`

## Run in Gitlab CI in docker runner

When running in a Gitlab CI with the docker runner we instruct Gitlab CI which docker image we want and set the required enviroment variables.  Here is an example `gitlab-ci.yml` file.  A couple details to notice are the `sed` command that replaces ssh git remotes with one that uses the `gitlab-ci-token` over https and that you will need to define the enviroment variables for the compiler and how it uses `IN_DOCKER` to let the script know it is already in the docker image:

```yaml
image: moveit/moveit:eloquent-ci
before_script:
  - git clone -b ros2 --quiet --depth 1 https://github.com/ros-planning/moveit_ci.git .moveit_ci
  - sed -i -r "s/ssh:\/\/git@gitlab\.company\.com:9000/https:\/\/gitlab-ci-token:${CI_JOB_TOKEN}@gitlab\.company\.com/g" ${CI_PROJECT_DIR}/repo_name.repos
  - export TRAVIS_BRANCH=$CI_COMMIT_REF_NAME
  - export CXX=c++
  - export CC=cc
  - export ROS_DISTRO=eloquent
  - export UPSTREAM_WORKSPACE=repo_name.repos
  - export IN_DOCKER=1
  - export CI_SOURCE_PATH=$PWD
  - export ROS_WS=${HOME}/ros_ws
  - mkdir $ROS_WS
test:
  tags:
    - docker-runner
  script:
    - .moveit_ci/travis.sh
```
