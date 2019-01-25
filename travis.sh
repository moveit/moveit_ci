#!/bin/bash

# Software License Agreement - BSD License
#
# Inspired by MoveIt! travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

# Note: ROS_REPOSITORY_PATH is no longer a valid option, use ROS_REPO. See README.md

export CI_SOURCE_PATH=$(pwd) # The repository code in this pull request that we are testing
export CI_PARENT_DIR=.moveit_ci  # This is the folder name that is used in downstream repositories in order to point to this repo.
export REPOSITORY_NAME=${PWD##*/}
export CATKIN_WS=/root/ws_moveit
export TRAVIS_GLOBAL_TIMEOUT=45  # 50min minus slack
export TRAVIS_GLOBAL_START_TIME=$(date +%s)
echo "---"
echo "\033[33;1mTesting branch '$TRAVIS_BRANCH' of '$REPOSITORY_NAME' on ROS '$ROS_DISTRO'\033[0m"

# Helper functions
source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/util.sh

# Run all CI in a Docker container
if ! [ "$IN_DOCKER" ]; then
    # Run BEFORE_DOCKER_SCRIPT
    if [ "${BEFORE_DOCKER_SCRIPT// }" != "" ]; then
        travis_run $BEFORE_DOCKER_SCRIPT
    fi

    # Choose the correct CI container to use
    case "$ROS_REPO" in
        ros-shadow-fixed)
            export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci-shadow-fixed
            ;;
        *)
            export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci
            ;;
    esac
    echo "Starting Docker image: $DOCKER_IMAGE"

    # Pull first to allow us to hide console output
    docker pull $DOCKER_IMAGE > /dev/null

    # Start Docker container
    docker run \
        -e TRAVIS \
        -e ROS_REPO \
        -e ROS_DISTRO \
        -e BEFORE_SCRIPT \
        -e CI_PARENT_DIR \
        -e CI_SOURCE_PATH \
        -e UPSTREAM_WORKSPACE \
        -e TRAVIS_BRANCH \
        -e TEST \
        -e TEST_BLACKLIST \
        -e CC \
        -e CXX \
        -e CFLAGS \
        -e CXXFLAGS \
        -v $(pwd):/root/$REPOSITORY_NAME \
        -v $HOME/.ccache:/root/.ccache \
        -t \
        $DOCKER_IMAGE \
        /bin/bash -c "cd /root/$REPOSITORY_NAME; source .moveit_ci/travis.sh;"
    return_value=$?

    if [ $return_value -eq 0 ]; then
        echo -e "\033[32;1mTravis script finished successfully\033[0m"
    else
        echo -e "\033[31;1mTravis script finished with errors\033[0m"
    fi
    exit $return_value
fi

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

# Define CC/CXX defaults and print compiler version info
export CC=${CC:-cc}
export CXX=${CXX:-c++}
$CXX --version

# Update the sources
travis_run apt-get -qq update

# Make sure the packages are up-to-date
travis_run apt-get -qq dist-upgrade

# Split for different tests
for t in $TEST; do
    case "$t" in
        clang-format)
            source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/check_clang_format.sh || exit 1
            exit 0 # This runs as an independent job, do not run regular travis test
            ;;
        clang-tidy-check)  # run clang-tidy along with compiler and report warning
            # Install clang-tidy
            travis_run apt-get -qq install -y clang-tidy
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_CXX_CLANG_TIDY=clang-tidy"
            ;;
        clang-tidy-fix)  # run clang-tidy -fix and report code changes in the end
            # Install clang-tidy
            travis_run apt-get -qq install -y clang-tidy
            # run-clang-tidy is part of clang-tools in Bionic
            travis_run_true apt-get -qq install -y clang-tools
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            ;;
        *)
            echo "Unknown TEST: $t"
            exit 1
            ;;
    esac
done
if [[ "$TEST" == *clang-tidy* ]] ; then
    # Provide a default .clang-tidy config file from MoveIt as a fallback for the whole workspace
    # Files within specific package repositories take precedence of this.
    travis_run wget -nv https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-tidy -O $CATKIN_WS/.clang-tidy
    travis_run cat $CATKIN_WS/.clang-tidy
fi

# Enable ccache
travis_run apt-get -qq install ccache
export PATH=/usr/lib/ccache:$PATH

# Install and run xvfb to allow for X11-based unittests on DISPLAY :99
travis_run apt-get -qq install xvfb mesa-utils
Xvfb -screen 0 640x480x24 :99 &
export DISPLAY=:99.0
travis_run_true glxinfo

# Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
travis_run rosdep update

# Create workspace
travis_run mkdir -p $CATKIN_WS/src
travis_run cd $CATKIN_WS/src

# Install dependencies necessary to run build using .rosinstall files
if [ ! "$UPSTREAM_WORKSPACE" ]; then
    export UPSTREAM_WORKSPACE="debian";
fi
case "$UPSTREAM_WORKSPACE" in
    debian)
        echo "Obtaining debian packages for all upstream dependencies."
        ;;
    http://* | https://*) # When UPSTREAM_WORKSPACE is an http url, use it directly
        travis_run wstool init .
        # Handle multiple rosintall entries.
        (  # parentheses ensure that IFS is automatically reset
            IFS=','  # Multiple URLs can be given separated by comma.
            for rosinstall in $UPSTREAM_WORKSPACE; do
                travis_run wstool merge -k $rosinstall
            done
        )
        ;;
    *) # Otherwise assume UPSTREAM_WORKSPACE is a local file path
        travis_run wstool init .
        if [ -e $CI_SOURCE_PATH/$UPSTREAM_WORKSPACE ]; then
            # install (maybe unreleased version) dependencies from source
            travis_run wstool merge file://$CI_SOURCE_PATH/$UPSTREAM_WORKSPACE
        else
            echo "Didn't find rosinstall file: $CI_SOURCE_PATH/$UPSTREAM_WORKSPACE. Aborting"
            exit 1
        fi
        ;;
esac

# download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the downstream is not in .rosinstall
    travis_run_true wstool rm $REPOSITORY_NAME
    # perform shallow checkout: only possible with wstool init
    travis_run mv .rosinstall rosinstall
    travis_run cat rosinstall
    travis_run wstool init --shallow . rosinstall
fi

# link in the repo we are testing
travis_run ln -s $CI_SOURCE_PATH .

# Debug: see the files in current folder
travis_run ls -a

# Run BEFORE_SCRIPT
if [ "${BEFORE_SCRIPT// }" != "" ]; then
    travis_run $BEFORE_SCRIPT
fi

# Install source-based package dependencies
travis_run rosdep install -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run cd $CATKIN_WS

echo -e "\033[33;1mBuilding Workspace\033[0m"
# Configure catkin
travis_run catkin config --extend /opt/ros/$ROS_DISTRO --install --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="-O3" $CMAKE_ARGS --

# Console output fix for: "WARNING: Could not encode unicode characters"
export PYTHONIOENCODING=UTF-8

# For a command that doesn’t produce output for more than 10 minutes, prefix it with travis_run_wait
travis_run_wait 60 catkin build --no-status --summarize || exit 1

travis_run ccache -s

# Source the new built workspace
travis_run source install/setup.bash;

# Choose which packages to run tests on
echo -e "\033[33;1mTesting Workspace\033[0m"
echo "Test blacklist: $TEST_BLACKLIST"
TEST_PKGS=$(catkin_topological_order $CATKIN_WS/src --only-names 2> /dev/null | grep -Fvxf <(echo "$TEST_BLACKLIST" | tr ' ;,' '\n') | tr '\n' ' ')

if [ -n "$TEST_PKGS" ]; then
    # Fix formatting of list of packages to work correctly with Travis
    IFS=' ' read -r -a TEST_PKGS <<< "$TEST_PKGS"
    echo "Test packages: ${TEST_PKGS[@]}"
    TEST_PKGS="--no-deps ${TEST_PKGS[@]}"

    # Run catkin package tests
    travis_run_wait catkin build --no-status --summarize --make-args tests -- $TEST_PKGS

    # Run non-catkin package tests
    travis_run_wait catkin build --catkin-make-args run_tests -- --no-status --summarize $TEST_PKGS

    # Show failed tests
    for file in $(catkin_test_results | grep "\.xml:" | cut -d ":" -f1); do
        travis_run cat $file
    done

    # Show test results summary and throw error if necessary
    travis_run catkin_test_results
else
    echo "No packages to test."
fi

# Run clang-tidy-fix check
case "$TEST" in
    *clang-tidy-fix*)
        source ${CI_SOURCE_PATH}/$CI_PARENT_DIR/check_clang_tidy.sh || exit 1
        ;;
esac
