#!/bin/bash
# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD License
#
# Inspired by MoveIt! travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

export MOVEIT_CI_DIR=$(dirname $0)  # path to the directory running the current script
export REPOSITORY_NAME=$(basename $PWD) # name of repository, travis originally checked out
export CATKIN_WS=${CATKIN_WS:-/root/ws_moveit} # location of catkin workspace

# Travis' default timeout for open source projects is 50 mins
# If your project has a larger timeout, specify this variable in your .travis.yml file!
MOVEIT_CI_TRAVIS_TIMEOUT=${MOVEIT_CI_TRAVIS_TIMEOUT:-47}  # 50min minus safety margin

# Helper functions
source ${MOVEIT_CI_DIR}/util.sh

# Run all CI in a Docker container
if ! [ "$IN_DOCKER" ]; then
    echo -e "${ANSI_YELLOW}Testing branch '$TRAVIS_BRANCH' of '$REPOSITORY_NAME' on ROS '$ROS_DISTRO'${ANSI_RESET}"
    # Run BEFORE_DOCKER_SCRIPT
    if [ "${BEFORE_DOCKER_SCRIPT// }" != "" ]; then
        travis_run --title "${ANSI_BOLD}Running BEFORE_DOCKER_SCRIPT${ANSI_THIN}" $BEFORE_DOCKER_SCRIPT
        result=$?
        test $result -ne 0 && echo -e "${ANSI_RED}Script failed with return value: $result. Aborting.${ANSI_RESET}" && exit 2
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
    echo -e "${ANSI_BOLD}Starting Docker image: $DOCKER_IMAGE${ANSI_RESET}"

    travis_run docker pull $DOCKER_IMAGE

    # Start Docker container
    docker run \
        -e TRAVIS \
        -e MOVEIT_CI_TRAVIS_TIMEOUT=$(travis_timeout $MOVEIT_CI_TRAVIS_TIMEOUT) \
        -e ROS_REPO \
        -e ROS_DISTRO \
        -e BEFORE_SCRIPT \
        -e CI_SOURCE_PATH=${CI_SOURCE_PATH:-/root/$REPOSITORY_NAME} \
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
        -w /root/$REPOSITORY_NAME \
        $DOCKER_IMAGE /root/$REPOSITORY_NAME/.moveit_ci/travis.sh
    return_value=$?

    echo
    case $return_value in
        0) echo -e "${ANSI_GREEN}Travis script finished successfully.${ANSI_RESET}" ;;
        124) echo -e "${ANSI_YELLOW}Timed out, but try again! Having saved cache results, Travis will probably succeed next time.${ANSI_RESET}\\n" ;;
        *) echo -e "${ANSI_RED}Travis script finished with errors.${ANSI_RESET}" ;;
    esac
    exit $return_value
fi

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

# Define CC/CXX defaults and print compiler version info
export CC=${CC:-cc}
export CXX=${CXX:-c++}
travis_run --title "${ANSI_RESET}$CXX compiler info" $CXX --version

travis_fold start update "Updating system packages"
# Update the sources
travis_run apt-get -qq update

# Make sure the packages are up-to-date
travis_run apt-get -qq dist-upgrade

# Split for different tests
for t in $(unify_list " ,;" "$TEST") ; do
    case "$t" in
        clang-format)
            travis_fold end update
            source ${MOVEIT_CI_DIR}/check_clang_format.sh || exit 2
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
            echo -e "${ANSI_RED}Unknown TEST: $t${ANSI_RESET}"
            exit 1
            ;;
    esac
done
[[ "$TEST" == *clang-tidy* ]] && travis_run apt-get -qq install -y clang-tidy # Install clang-tidy (once for all clang-tidy-* checks)

# Enable ccache
travis_run apt-get -qq install ccache
export PATH=/usr/lib/ccache:$PATH

# Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
travis_run rosdep update

travis_fold end update

# Install and run xvfb to allow for X11-based unittests on DISPLAY :99
travis_fold start xvfb "Starting virtual X11 server to allow for X11-based unit tests"
travis_run apt-get -qq install xvfb mesa-utils
travis_run "Xvfb -screen 0 640x480x24 :99 &"
export DISPLAY=:99.0
travis_run_true glxinfo
travis_fold end xvfb

# Create workspace
travis_fold start catkin.ws "Setting up catkin workspace"
travis_run_simple mkdir -p $CATKIN_WS/src
travis_run_simple cd $CATKIN_WS/src

if [ "$TEST" == clang-tidy-check ] ; then
    # clang-tidy-check essentially runs during the build process for *all* packages.
    # However, we only want to check one repository ($CI_SOURCE_PATH).
    # Thus, we provide a dummy .clang-tidy config file as a fallback for the whole workspace
    travis_run_simple --no-assert cp $MOVEIT_CI_DIR/.dummy-clang-tidy $CATKIN_WS/src/.clang-tidy
fi
if [[ "$TEST" == clang-tidy-* ]] ; then
    # Ensure a useful .clang-tidy config file is present in the to-be-tested repo ($CI_SOURCE_PATH)
    [ -f $CI_SOURCE_PATH/.clang-tidy ] || \
        travis_run --title "Fetching default clang-tidy config from MoveIt" \
            wget -nv https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-tidy -O $CI_SOURCE_PATH/.clang-tidy
    travis_run --display "Applying the following clang-tidy checks:" cat $CI_SOURCE_PATH/.clang-tidy
fi

# Pull additional packages into the catkin workspace
travis_run wstool init .
for item in $(unify_list " ,;" ${UPSTREAM_WORKSPACE:-debian}) ; do
   case "$item" in
      debian)
         echo "Obtaining debian packages for all upstream dependencies."
         break ;;
      https://github.com/*) # clone from github
         travis_run_true git clone -q --depth 1 $item
         test $? -ne 0 && echo -e "${ANSI_RED}Failed clone repository. Aborting.${ANSI_RESET}" && exit 2
         continue ;;
      http://* | https://* | file://*) ;; # use url as is
      *) item="file://$CI_SOURCE_PATH/$item" ;; # turn into proper url
   esac
   travis_run_true wstool merge -k $item
   test $? -ne 0 && echo -e "${ANSI_RED}Failed to find rosinstall file. Aborting.${ANSI_RESET}" && exit 2
done

# Download upstream packages into workspace
if [ -e .rosinstall ]; then
    # ensure that the to-be-tested package is not in .rosinstall
    travis_run_true wstool rm $REPOSITORY_NAME
    # perform shallow checkout: only possible with wstool init
    travis_run_simple mv .rosinstall rosinstall
    travis_run cat rosinstall
    travis_run wstool init --shallow . rosinstall
fi

# Link in the repo we are testing
# Use travis_run_impl to accept failure
travis_run_impl --timing --title "${ANSI_RESET}Symlinking to-be-tested repo $CI_SOURCE_PATH into catkin workspace" \
    ln -s $CI_SOURCE_PATH .
# Allow failure if (and only if) CI_SOURCE_PATH != REPOSITORY_NAME
if [ $? -ne 0 -a "$(basename $CI_SOURCE_PATH)" == $REPOSITORY_NAME ] ; then
   echo -e "${ANSI_RED}Aborting.${ANSI_RESET}" && exit 2
fi

# Debug: see the files in current folder
travis_run --title "${ANSI_RESET}List files catkin workspace's source folder" ls -a

# Run BEFORE_SCRIPT
if [ "${BEFORE_SCRIPT// }" != "" ]; then
    travis_run --title "${ANSI_BOLD}Running BEFORE_SCRIPT${ANSI_THIN}" $BEFORE_SCRIPT
    result=$?
    test $result -ne 0 && echo -e "${ANSI_RED}Script failed with return value: $result. Aborting.${ANSI_RESET}" && exit 2
fi

# Install source-based package dependencies
travis_run rosdep install -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

# Change to base of workspace
travis_run_simple cd $CATKIN_WS
travis_fold end catkin.ws

echo -e "${ANSI_GREEN}Building Workspace${ANSI_RESET}"
# Configure catkin
travis_run --title "catkin config $CMAKE_ARGS" catkin config --extend /opt/ros/$ROS_DISTRO --install --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="-O3" $CMAKE_ARGS --

# Console output fix for: "WARNING: Could not encode unicode characters"
export PYTHONIOENCODING=UTF-8

# For a command that doesn’t produce output for more than 10 minutes, prefix it with travis_run_wait
travis_run_wait 60 --title "catkin build" catkin build --no-status --summarize

travis_run --title "ccache statistics" ccache -s

echo -e "${ANSI_GREEN}Testing Workspace${ANSI_RESET}"
travis_run_simple --title "Sourcing newly built install space" source install/setup.bash

# Choose which packages to run tests on
echo "Test blacklist: $TEST_BLACKLIST"
TEST_PKGS=$(filter-out "$TEST_BLACKLIST" $(catkin_topological_order $CATKIN_WS/src --only-names))

if [ -n "$TEST_PKGS" ]; then
    echo "Test packages: $TEST_PKGS"
    TEST_PKGS="--no-deps $TEST_PKGS"

    # Build tests
    travis_run_wait --title "catkin build tests" catkin build --no-status --summarize --make-args tests -- $TEST_PKGS
    # Run tests, suppressing the output (confuses Travis display?)
    travis_run_wait --title "catkin run_tests" "catkin build --catkin-make-args run_tests -- --no-status --summarize $TEST_PKGS 2>/dev/null"

    # Show failed tests
    travis_fold start test.results "catkin_test_results"
    for file in $(catkin_test_results | grep "\.xml:" | cut -d ":" -f1); do
        travis_run --display "Test log of $file" cat $file
    done
    travis_fold end test.results

    # Show test results summary and throw error if necessary
    catkin_test_results || exit 2
else
    echo "No packages to test."
fi

# Run clang-tidy-fix check
case "$TEST" in
    *clang-tidy-fix*)
        source ${MOVEIT_CI_DIR}/check_clang_tidy.sh || exit 2
        ;;
esac
