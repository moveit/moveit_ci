#!/bin/bash

# Software License Agreement (BSD License)
#
# Copyright (c) 2016, Isaac I. Y. Saito, Dave Coleman
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#       * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#       * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#       * Neither the name of the Isaac I. Y. Saito, nor the names
#       of its contributors may be used to endorse or promote products derived
#       from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Greatly inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Greatly inspired by ROS Industrial: https://github.com/ros-industrial/industrial_ci
#
# Author: Isaac I. Y. Saito, Dave Coleman
#
# Variables that are not meant to be exposed externally from this script may be lead by underscore.

# Define some env vars that need to come earlier than util.sh
export CI_SOURCE_PATH=$(pwd)
export CI_PARENT_DIR=.ci_config  # This is the folder name that is used in downstream repositories in order to point to this repo.
export HIT_ENDOFSCRIPT=false
export DOWNSTREAM_REPO_NAME=${PWD##*/}

# Helper functions
source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

if [[ "$ROS_DISTRO" != "kinetic" ]]; then
    echo "This script only supports kinetic currently. TODO add docker containers for previous ROS versions";
    exit 1;
fi

# The Dockerfile in this repository defines a Ubuntu 16.04 container with ROS pre-installed
if ! [ "$IN_DOCKER" ]; then

  # Pull first to allow us to hide console output
  docker pull davetcoleman/industrial_ci > /dev/null

  # Start Docker container
  docker run \
      -e ROS_REPOSITORY_PATH \
      -e ROS_DISTRO \
      -e ADDITIONAL_DEBS \
      -e BEFORE_SCRIPT \
      -e CI_PARENT_DIR \
      -e UPSTREAM_WORKSPACE \
      -v $(pwd):/root/$DOWNSTREAM_REPO_NAME davetcoleman/industrial_ci \
      /bin/bash -c "cd /root/$DOWNSTREAM_REPO_NAME; source .ci_config/travis.sh;"
  retval=$?

  if [ $retval -eq 0 ]; then
      echo "ROS $ROS_DISTRO Docker container finished successfully"
      HIT_ENDOFSCRIPT=true;
      exit 0
  fi
  echo "ROS $ROS_DISTRO Docker container finished with errors"
  exit -1 # error
fi

# Set apt repo - this was already defined in OSRF image but we probably want shadow-fixed
if [ ! "$ROS_REPOSITORY_PATH" ]; then # If not specified, use ROS Shadow repository http://wiki.ros.org/ShadowRepository
    export ROS_REPOSITORY_PATH="http://packages.ros.org/ros-shadow-fixed/ubuntu";
fi
sudo -E sh -c 'echo "deb $ROS_REPOSITORY_PATH `lsb_release -cs` main" > /etc/apt/sources.list.d/ros-latest.list'

# Update the sources
travis_run sudo apt-get -qq update

# If more DEBs needed during preparation, define ADDITIONAL_DEBS variable where you list the name of DEB(S, delimitted by whitespace)
if [ "$ADDITIONAL_DEBS" ]; then
    travis_run sudo apt-get -qq install -q -y $ADDITIONAL_DEBS;
fi

# Setup rosdep
# Note: "rosdep init" is already setup in base ROS Docker image
travis_run rosdep update

# Create workspace
travis_run mkdir -p ~/ros/ws_$DOWNSTREAM_REPO_NAME/src
travis_run cd ~/ros/ws_$DOWNSTREAM_REPO_NAME/src

# Install any prerequisites or dependencies necessary to run build
if [ ! "$UPSTREAM_WORKSPACE" ]; then
    export UPSTREAM_WORKSPACE="debian";
fi
case "$UPSTREAM_WORKSPACE" in
    debian)
        echo "Obtain deb binary for upstream packages."
        ;;
    http://* | https://*) # When UPSTREAM_WORKSPACE is an http url, use it directly
        travis_run wstool init .
        travis_run wstool merge $UPSTREAM_WORKSPACE
        ;;
    *) # Otherwise assume UPSTREAM_WORKSPACE is a local file path
        travis_run wstool init .
        if [ -e $CI_SOURCE_PATH/$UPSTREAM_WORKSPACE ]; then
            # install (maybe unreleased version) dependencies from source
            travis_run wstool merge file://$CI_SOURCE_PATH/$UPSTREAM_WORKSPACE
        fi
        ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    travis_run wstool rm $DOWNSTREAM_REPO_NAME || true
    travis_run cat .rosinstall
    travis_run wstool update
fi

# CI_SOURCE_PATH is the path of the downstream repository that we are testing. Link it to the catkin workspace
travis_run ln -s $CI_SOURCE_PATH .

# source setup.bash
travis_run source /opt/ros/$ROS_DISTRO/setup.bash

# Run before script
if [ "${BEFORE_SCRIPT// }" != "" ]; then sh -c "${BEFORE_SCRIPT}"; fi

# Install source-based package dependencies
travis_run sudo rosdep install -r -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run cd ~/ros/ws_$DOWNSTREAM_REPO_NAME/

# re-source setup.bash for setting environmet vairable for package installed via rosdep
#travis_run source /opt/ros/$ROS_DISTRO/setup.bash

# Configure catkin to use install configuration
travis_run catkin config --install

# Console output fix for: "WARNING: Could not encode unicode characters"
PYTHONIOENCODING=UTF-8

# For a command that doesn’t produce output for more than 10 minutes, prefix it with my_travis_wait
echo "Running catkin build..."
my_travis_wait 60 catkin build --no-status --summarize

# Source the new built workspace
travis_run source install/setup.bash;

# Only run tests on the current repo's packages
TEST_PKGS=$(catkin_topological_order $CI_SOURCE_PATH --only-names)
if [ -n "$TEST_PKGS" ]; then TEST_PKGS="--no-deps $TEST_PKGS"; fi
if [ "$ALLOW_TEST_FAILURE" != "true" ]; then ALLOW_TEST_FAILURE=false; fi
echo "Running tests for packages: '$TEST_PKGS'"

# Re-build workspace with tests
travis_run catkin build --no-status --summarize --make-args tests -- $TEST_PKGS

# Run tests
travis_run catkin run_tests --no-status --summarize $TEST_PKGS
travis_run catkin_test_results

echo "Travis script has finished successfully"
HIT_ENDOFSCRIPT=true
exit 0
