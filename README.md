# MoveIt Continous Integration
Common Travis CI configuration for MoveIt! project

- Uses Docker for all Distros
  - Travis does not currently support Ubuntu 16.04
  - Based on OSRF's pre-build ROS Docker container to save setup time
  - Uses MoveIt's pre-build Docker container to additionally save setup time
- Simple - only contains features needed for MoveIt!
- Clean Travis log files - looks similiar to a regular .travis.yml file
- Runs tests for the current repo, e.g. if testing moveit\_core only runs tests for moveit\_core
- Builds into install space
- Prevents Travis from timing out and from running out of log space, even for huge builds (all of MoveIt!)

## Usage

Create a ``.travis.yml`` file in the base of you repo similar to:

```
# This config file for Travis CI utilizes https://github.com/davetcoleman/moveit_ci/ package.
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
      - dave@dav.ee
env:
  matrix:
    - ROS_DISTRO="kinetic"  ROS_REPOSITORY_PATH=http://packages.ros.org/ros/ubuntu              UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit_docs/kinetic-devel/moveit.rosinstall
    - ROS_DISTRO="kinetic"  ROS_REPOSITORY_PATH=http://packages.ros.org/ros-shadow-fixed/ubuntu UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit_docs/kinetic-devel/moveit.rosinstall
matrix:
  allow_failures:
    - env: ROS_DISTRO="kinetic" ROS_REPOSITORY_PATH=http://packages.ros.org/ros/ubuntu              UPSTREAM_WORKSPACE=https://raw.githubusercontent.com/ros-planning/moveit_docs/kinetic-devel/moveit.rosinstall
before_script:
  - git clone -q https://github.com/davetcoleman/moveit_ci.git .moveit_ci
script:
  - source .moveit_ci/travis.sh
```
