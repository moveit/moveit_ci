#!/bin/bash

# Software License Agreement - BSD License
#
# Inspired by MoveIt! travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

export CI_SOURCE_PATH=$(pwd)
export CI_PARENT_DIR=.moveit_ci  # This is the folder name that is used in downstream repositories in order to point to this repo.
export HIT_ENDOFSCRIPT=false
export REPOSITORY_NAME=${PWD##*/}

echo "Testing branch $TRAVIS_BRANCH of $REPOSITORY_NAME on $ROS_DISTRO"

# Helper functions
source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

# Run all CI in a Docker container
if ! [ "$IN_DOCKER" ]; then
    # Pull first to allow us to hide console output
    #docker pull moveit/moveit_docker:moveit-$ROS_DISTRO-ci > /dev/null
    docker pull moveit/moveit_docker:moveit-$ROS_DISTRO-ci

    # Start Docker container
    docker run \
        -e ROS_REPOSITORY_PATH \
        -e ROS_REPO \
        -e ROS_DISTRO \
        -e BEFORE_SCRIPT \
        -e CI_PARENT_DIR \
        -e UPSTREAM_WORKSPACE \
        -e TRAVIS_BRANCH \
        -e TEST_BLACKLIST \
        -v $(pwd):/root/$REPOSITORY_NAME moveit/moveit_docker:moveit-$ROS_DISTRO-ci \
        /bin/bash -c "cd /root/$REPOSITORY_NAME; source .moveit_ci/travis.sh;"
    return_value=$?

    if [ $return_value -eq 0 ]; then
        echo "ROS $ROS_DISTRO Docker container finished successfully"
        HIT_ENDOFSCRIPT=true;
        exit 0
    fi
    echo "ROS $ROS_DISTRO Docker container finished with errors"
    exit 1 # error
fi

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

# This is the new more compact way to specify what ros repository to use
case "$ROS_REPO" in
    ros-shadow-fixed)
        travis_run export ROS_REPOSITORY_PATH="http://packages.ros.org/ros-shadow-fixed/ubuntu";
        ;;
    ros)
        travis_run export ROS_REPOSITORY_PATH="http://packages.ros.org/ros/ubuntu";
        ;;
    # else: default to specified ROS_REPOSITORY_PATH or default one below
esac

# Set apt repo - this was already defined in OSRF image but we probably want shadow-fixed
if [ ! "$ROS_REPOSITORY_PATH" ]; then # If not specified, use ROS Shadow repository http://wiki.ros.org/ShadowRepository
    travis_run export ROS_REPOSITORY_PATH="http://packages.ros.org/ros-shadow-fixed/ubuntu";
else
    travis_run echo "$ROS_REPOSITORY_PATH"
fi

# Note: cannot use "travis_run" with this command because of the various quote symbols
sudo -E sh -c 'echo "deb $ROS_REPOSITORY_PATH `lsb_release -cs` main" > /etc/apt/sources.list.d/ros-latest.list'

# Update the sources
travis_run sudo apt-get -qq update

# Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
travis_run rosdep update

# Create workspace
travis_run mkdir -p ~/ros/ws_$REPOSITORY_NAME/src
travis_run cd ~/ros/ws_$REPOSITORY_NAME/src

# Install dependencies necessary to run build using .rosinstall files
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
        else
            echo "No rosinstall file found, aborting" && exit 1
        fi
        ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    # the exclamation mark means to ignore errors
    travis_run_true wstool rm $REPOSITORY_NAME
    travis_run cat .rosinstall
    travis_run wstool update
fi

# link in the repo we are testing
travis_run ln -s $CI_SOURCE_PATH .

# Debug: see the files in current folder
travis_run ls -a

# Run before script
if [ "${BEFORE_SCRIPT// }" != "" ]; then
    travis_run sh -c "${BEFORE_SCRIPT}";
fi

# Install source-based package dependencies
travis_run sudo rosdep install -r -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run cd ~/ros/ws_$REPOSITORY_NAME/

# Configure catkin
travis_run catkin config --extend /opt/ros/$ROS_DISTRO --install --cmake-args -DCMAKE_BUILD_TYPE=Release

# Console output fix for: "WARNING: Could not encode unicode characters"
export PYTHONIOENCODING=UTF-8

# For a command that doesn’t produce output for more than 10 minutes, prefix it with my_travis_wait
my_travis_wait 60 catkin build --no-status --summarize || exit 1

# Source the new built workspace
travis_run source install/setup.bash;

# Only run tests on the current repo's packages
echo "Test blacklist: $TEST_BLACKLIST"
TEST_PKGS=$(catkin_topological_order src --only-names | grep -Fvxf <(echo "$TEST_BLACKLIST" | tr ' ;,' '\n'))
if [ -n "$TEST_PKGS" ]; then
    TEST_PKGS="--no-deps $TEST_PKGS";
fi

# Re-build workspace with tests
travis_run catkin build --no-status --summarize --make-args tests -- $TEST_PKGS

# Run tests
travis_run catkin run_tests --no-status --summarize $TEST_PKGS
travis_run catkin_test_results

echo "Travis script has finished successfully"
HIT_ENDOFSCRIPT=true
exit 0
