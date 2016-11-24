# MoveIt Continous Integration
Common Travis CI configuration for MoveIt! project

Authors: Dave Coleman, Isaac I. Y. Saito, Robert Haschke

- Uses Docker for all Distros
  - Travis does not currently support Ubuntu 16.04
  - Based on OSRF's pre-build ROS Docker container to save setup time
  - Uses MoveIt's pre-build Docker container to additionally save setup time
- Simple - only contains features needed for MoveIt!
- Clean Travis log files - looks similiar to a regular .travis.yml file
- Runs tests for the current repo, e.g. if testing moveit\_core only runs tests for moveit\_core
- Builds into install space
- Prevents Travis from timing out and from running out of log space, even for huge builds (all of MoveIt!)
- Supports Ubuntu Wily

[![Build Status](https://travis-ci.org/ros-planning/moveit_ci.svg?branch=master)](https://travis-ci.org/ros-planning/moveit_ci)

## Usage

Create a ``.travis.yml`` file in the base of you repo similar to:

```
# This config file for Travis CI utilizes https://github.com/ros-planning/moveit_ci/ package.
sudo: required
dist: trusty
services:
  - docker
language: generic
compiler:
  - gcc
notifications:
  email:
    recipients:
      # - user@email.com
env:
  matrix:
    - ROS_DISTRO=kinetic  ROS_REPO=ros              UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit/kinetic-devel/moveit.rosinstall
    - ROS_DISTRO=kinetic  ROS_REPO=ros-wily         UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit/kinetic-devel/moveit.rosinstall
    - ROS_DISTRO=kinetic  ROS_REPO=ros-shadow-fixed UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit/kinetic-devel/moveit.rosinstall
    - TEST=clang-format
matrix:
  allow_failures:
    - env: ROS_DISTRO=kinetic  ROS_REPO=ros              UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit/kinetic-devel/moveit.rosinstall
before_script:
  - git clone -q https://github.com/ros-planning/moveit_ci.git .moveit_ci
script:
  - source .moveit_ci/travis.sh
```

## Configurations

- ROS_DISTRO: (required) which version of ROS i.e. kinetic
- ROS_REPO: (default: ``ros-shadow-fixed``) install ROS debians from either regular release (``ros``) or from shadow-fixed, i.e. http://packages.ros.org/ros-shadow-fixed/ubuntu. Also has option for testing Ubuntu Wily via ``ros-wily`` option
- BEFORE_SCRIPT: (default: not set): Used to specify shell commands or scripts that run before building packages.
- UPSTREAM_WORKSPACE (default: debian): When set as "file", the dependended packages that need to be built from source are downloaded based on a .rosinstall file in your repository. When set to a "http" URL, this downloads the rosinstall configuration from an http location
- TEST_BLACKLIST: Allow certain tests to be skipped if necessary (not recommended)
- TEST: allow other tests to be run, such as code format checking using clang-format

More configurations as seen in [industrial_ci](https://github.com/ros-industrial/industrial_ci) can be added in the future.

## Removed Configuration

- ROS_REPOSITORY\_PATH: (UNSUPPORTED) replaced by ROS\_REPO

## Clang-Format

A new test is available that checks if the code is properly formatted as specified in the clang-format file found in ``.clang-format``. Use ``TEST=clang-format`` to enable this test.

## Running Locally For Testing

To manually run the moveit_ci script without Travis (presumably for testing), we will demonstrate with an example using the full moveit repo in this exact folder structure:

First clone any MoveIt!-related repo you want to test:

    cd ~/
    git clone https://github.com/ros-planning/moveit
    cd moveit

Next clone the CI script:

    git clone https://github.com/ros-planning/moveit_ci .moveit_ci

Manually define the necessary environmental variables:

    export TRAVIS_BRANCH=kinetic-devel
    export ROS_DISTRO=kinetic
    export UPSTREAM_WORKSPACE=moveit.rosinstall
    export ROS_REPO=ros-shadow-fixed

Start the script

    .moveit_ci/travis.sh
