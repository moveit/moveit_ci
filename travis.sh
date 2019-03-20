#!/bin/bash
# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD License
#
# Inspired by MoveIt! travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

export MOVEIT_CI_DIR=$(dirname ${BASH_SOURCE:-$0})  # path to the directory running the current script
export REPOSITORY_NAME=$(basename $PWD) # name of repository, travis originally checked out
export ROS_WS=${ROS_WS:-/root/ws_moveit} # location of ROS workspace

# Travis' default timeout for open source projects is 50 mins
# If your project has a larger timeout, specify this variable in your .travis.yml file!
MOVEIT_CI_TRAVIS_TIMEOUT=${MOVEIT_CI_TRAVIS_TIMEOUT:-47}  # 50min minus safety margin

# Helper functions
source ${MOVEIT_CI_DIR}/util.sh

# usage: run_script BEFORE_SCRIPT  or run_script BEFORE_DOCKER_SCRIPT
function run_script() {
   local script
   eval "script=\$$1"  # fetch value of variable passed in $1 (double indirection)
   if [ "${script// }" != "" ]; then  # only run when non-empty
      travis_run --title "$(colorize BOLD Running $1)" $script
      result=$?
      test $result -ne 0 && echo -e $(colorize RED "$1 failed with return value: $result. Aborting.") && exit 2
   fi
}

function run_docker() {
   echo -e $(colorize YELLOW "Testing branch '$TRAVIS_BRANCH' of '$REPOSITORY_NAME' on ROS '$ROS_DISTRO'")
   run_script BEFORE_DOCKER_SCRIPT

    # Choose the docker container to use
    case "${ROS_REPO:-ros}" in
       ros) export DOCKER_IMAGE=moveit/moveit2:$ROS_DISTRO-ci ;;
       *) echo -e $(colorize RED "Unsupported ROS_REPO=$ROS_REPO. Use 'ros'"); exit 1 ;;
    esac

    echo -e $(colorize BOLD "Starting Docker image: $DOCKER_IMAGE")
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
        -e WARNINGS_OK \
        -e ABI_BASE_URL \
        -e CC=${CC_FOR_BUILD:-${CC:-cc}} \
        -e CXX=${CXX_FOR_BUILD:-${CXX:-c++}} \
        -e CFLAGS \
        -e CXXFLAGS \
        -v $(pwd):/root/$REPOSITORY_NAME \
        -v $HOME/.ccache:/root/.ccache \
        -t \
        -w /root/$REPOSITORY_NAME \
        $DOCKER_IMAGE /root/$REPOSITORY_NAME/.moveit_ci/travis.sh
    result=$?

    echo
    case $result in
        0) echo -e $(colorize GREEN "Travis script finished successfully.") ;;
        124) echo -e $(colorize YELLOW "Timed out, but try again! Having saved cache results, Travis will probably succeed next time.") ;;
        *) echo -e $(colorize RED "Travis script finished with errors.") ;;
    esac
    exit $result
}

function update_system() {
   travis_fold start update "Updating system packages"
   # Update the sources
   travis_run apt-get -qq update

   # Make sure the packages are up-to-date
   travis_run apt-get -qq dist-upgrade

   # Install clang-tidy stuff if needed
   [[ "$TEST" == *clang-tidy* ]] && travis_run apt-get -qq install -y clang-tidy
   # run-clang-tidy is part of clang-tools in Bionic, but not in Xenial -> ignore failure
   [ "$TEST" == *clang-tidy-fix* ] && travis_run_true apt-get -qq install -y clang-tools
   # Install abi-compliance-checker if needed
   [[ "$TEST" == *abi* ]] && travis_run_true apt-get -qq install -y abi-dumper abi-compliance-checker links
   # Enable ccache
   travis_run apt-get -qq install ccache
   export PATH=/usr/lib/ccache:$PATH

   # Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
   travis_run rosdep update

   travis_fold end update
}

function prepare_or_run_early_tests() {
   # Check for different tests. clang-format will trigger an early exit
   # However, they can only run when $CI_SOURCE_PATH is already available. If not try later again.
   if ! [ -d "$CI_SOURCE_PATH" ] ; then return 0; fi

   # EARLY_RESULT="" -> no early exit, EARLY_RESULT=0 -> early success, otherwise early failure
   local EARLY_RESULT
   for t in $(unify_list " ,;" "$TEST") ; do
      case "$t" in
         clang-format)
            (source ${MOVEIT_CI_DIR}/check_clang_format.sh) # run in subshell to not exit
            EARLY_RESULT=$(( ${EARLY_RESULT:-0} + $? ))
            ;;
         clang-tidy-check)  # run clang-tidy along with compiler and report warning
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_CXX_CLANG_TIDY=clang-tidy"
            ;;
         clang-tidy-fix)  # run clang-tidy -fix and report code changes in the end
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            ;;
         abi)  # abi-checker requires debug symbols
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_BUILD_TYPE=RelWithDebInfo"
            ;;
         *)
            echo -e $(colorize RED "Unknown TEST: $t")
            EARLY_RESULT=$(( ${EARLY_RESULT:-0} + 1 ))
            ;;
      esac
   done
   test -n "$EARLY_RESULT" && exit $EARLY_RESULT
}

# Install and run xvfb to allow for X11-based unittests on DISPLAY :99
function run_xvfb() {
   travis_fold start xvfb "Starting virtual X11 server to allow for X11-based unit tests"
   travis_run apt-get -qq install xvfb mesa-utils
   travis_run "Xvfb -screen 0 640x480x24 :99 &"
   export DISPLAY=:99.0
   travis_run_true glxinfo -B
   travis_fold end xvfb
}

function prepare_ros_workspace() {
   travis_fold start ros.ws "Setting up ROS workspace"
   travis_run_simple mkdir -p $ROS_WS/src
   travis_run_simple cd $ROS_WS/src

   # Pull additional packages into the ros workspace
   travis_run wstool init .
   for item in $(unify_list " ,;" ${UPSTREAM_WORKSPACE:-debian}) ; do
      echo "$item"
      case "$item" in
         debian)
            echo "Obtaining debian packages for all upstream dependencies."
            break ;;
         https://github.com/*) # clone from github
            # extract url and optional branch from item=<url>#<branch>
            item="${item}#"
            url=${item%%#*}
            branch=${item#*#}; branch=${branch%#}; branch=${branch:+--branch ${branch}}
            travis_run_true git clone -q --depth 1 $branch $url
            test $? -ne 0 && echo -e "$(colorize RED Failed clone repository. Aborting.)" && exit 2
            continue ;;
         http://* | https://* | file://*) ;; # use url as is
         *) item="file://$CI_SOURCE_PATH/$item" ;; # turn into proper url
      esac
      travis_run_true wstool merge -k $item
      test $? -ne 0 && echo -e "$(colorize RED Failed to find rosinstall file. Aborting.)" && exit 2
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
   if [ "$(dirname $CI_SOURCE_PATH)" != $PWD ] ; then
      travis_run_simple --title "Symlinking to-be-tested repo $CI_SOURCE_PATH into ROS workspace" ln -s $CI_SOURCE_PATH .
   fi

   # Fetch clang-tidy configs
   if [ "$TEST" == clang-tidy-check ] ; then
      # clang-tidy-check essentially runs during the build process for *all* packages.
      # However, we only want to check one repository ($CI_SOURCE_PATH).
      # Thus, we provide a dummy .clang-tidy config file as a fallback for the whole workspace
      travis_run_simple --no-assert cp $MOVEIT_CI_DIR/.dummy-clang-tidy $ROS_WS/src/.clang-tidy
   fi
   if [[ "$TEST" == clang-tidy-* ]] ; then
      # Ensure a useful .clang-tidy config file is present in the to-be-tested repo ($CI_SOURCE_PATH)
      [ -f $CI_SOURCE_PATH/.clang-tidy ] || \
         travis_run --title "Fetching default clang-tidy config from MoveIt" \
                    wget -nv https://raw.githubusercontent.com/ros-planning/moveit2/moveit2-ci/.clang-tidy \
                         -O $CI_SOURCE_PATH/.clang-tidy
      travis_run --display "Applying the following clang-tidy checks:" cat $CI_SOURCE_PATH/.clang-tidy
   fi

   # run BEFORE_SCRIPT, which might modify the workspace further
   run_script BEFORE_SCRIPT

   # For debugging: list the files in workspace's source folder
   travis_run_simple cd $ROS_WS/src
   travis_run --title "List files in ROS workspace's source folder" ls --color=auto -alhF

   # Install source-based package dependencies
   travis_run rosdep install -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

   # Change to base of workspace
   travis_run_simple cd $ROS_WS

   travis_fold end ros.ws
}

function build_workspace() {
   echo -e $(colorize GREEN Building Workspace)

   # Console output fix for: "WARNING: Could not encode unicode characters"
   export PYTHONIOENCODING=UTF-8

   # For a command that doesn’t produce output for more than 10 minutes, prefix it with travis_run_wait
   # TODO(mlautman): implement `--packages-up-to $TEST_PKG` like functionality
   travis_run_wait 60 --title "colcon build" colcon build --symlink-install --event-handlers console_direct+

   # Allow to verify ccache usage
   travis_run --title "ccache statistics" ccache -s
}

function test_workspace() {
   echo -e $(colorize GREEN Testing Workspace)
   travis_run_simple --title "Sourcing newly built install space" source install/setup.bash

   # Run tests, suppressing the output (confuses Travis display?)
   # TODO(mlautman): implement `--packages-select $TEST_PKG` like functionality
   travis_run_wait --title "colcon test" "colcon test --return-code-on-test-failure --event-handlers console_direct+ 2>/dev/null"


   # Show failed tests
   # travis_fold start test.results "colcon test results"

   # TODO(mlautman): parse test results and report success/failure
   # Show test results summary and throw error if necessary
   # TODO(mlautman): Is this needed?
   # # travis_run echo "TODO(mlautman): parse test results and report success/failure"
   # if [[ "$?" -ne "0" ]]; then
   #  exit 2
   # fi
   # travis_fold end test.results
}

###########################################################################################################
# main program

# This repository has some dummy ROS packages in folder test_pkgs, which are needed for unit testing only.
# To not clutter normal builds, we just create a COLCON_IGNORE file in that folder.
# A unit test can be recognized from the presence of the environment variable $TEST_PKG (see unit_tests.sh)
test -z "$TEST_PKG" && touch ${MOVEIT_CI_DIR}/test_pkgs/COLCON_IGNORE # not a unit test build

# Re-run the script in a Docker container
if ! [ "$IN_DOCKER" ]; then run_docker; fi

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

# Prepend current dir if path is not yet absolute
[[ "$MOVEIT_CI_DIR" != /* ]] && MOVEIT_CI_DIR=$PWD/$MOVEIT_CI_DIR
if [[ "$CI_SOURCE_PATH" != /* ]] ; then
   # If CI_SOURCE_PATH is not yet absolute
   if [ -d "$PWD/$CI_SOURCE_PATH" ] ; then
      CI_SOURCE_PATH=$PWD/$CI_SOURCE_PATH  # prepend with current dir, if that's feasible
   else
      # otherwise assume the folder will be created in $ROS_WS/src
      CI_SOURCE_PATH=$ROS_WS/src/$CI_SOURCE_PATH
   fi
fi

# normalize WARNINGS_OK to 0/1. Originally we accept true, yes, or 1 to allow warnings.
test ${WARNINGS_OK:=true} == true -o "$WARNINGS_OK" == 1 -o "$WARNINGS_OK" == yes && WARNINGS_OK=1 || WARNINGS_OK=0

# Define CC/CXX defaults and print compiler version info
travis_run --title "CXX compiler info" $CXX --version

update_system
prepare_or_run_early_tests
run_xvfb
prepare_ros_workspace
prepare_or_run_early_tests

build_workspace
test_workspace

# Run all remaining tests
for t in $(unify_list " ,;" "$TEST") ; do
   case "$t" in
      clang-tidy-fix)
         (source ${MOVEIT_CI_DIR}/check_clang_tidy.sh)
         test $? -eq 0 || result=$(( ${result:-0} + 1 ))
         ;;
      abi)
         (source ${MOVEIT_CI_DIR}/check_abi.sh)
         test $? -eq 0 || result=$(( ${result:-0} + 1 ))
         ;;
   esac
done
# Run warnings check
(source ${MOVEIT_CI_DIR}/check_warnings.sh)
test $? -eq 0 || result=$(( ${result:-0} + 1 ))

exit ${result:-0}
