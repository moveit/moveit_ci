#!/bin/bash -u
# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD License
#
# Inspired by MoveIt travis https://github.com/ros-planning/moveit_core/blob/09bbc196dd4388ac8d81171620c239673b624cc4/.travis.yml
# Inspired by JSK travis https://github.com/jsk-ros-pkg/jsk_travis
# Inspired by ROS Industrial https://github.com/ros-industrial/industrial_ci
#
# Author:  Dave Coleman, Isaac I. Y. Saito, Robert Haschke

export MOVEIT_CI_DIR=$(dirname ${BASH_SOURCE:-$0})  # path to the directory running the current script
export REPOSITORY_NAME=$(basename $PWD) # name of repository, travis originally checked out

# Travis' default timeout for open source projects is 50 mins
# If your project has a larger timeout, specify this variable in your .travis.yml file!
MOVEIT_CI_TRAVIS_TIMEOUT=${MOVEIT_CI_TRAVIS_TIMEOUT:-47}  # 50min minus safety margin

# Helper functions
source ${MOVEIT_CI_DIR}/util.sh

# usage: run_script BEFORE_SCRIPT  or run_script BEFORE_DOCKER_SCRIPT
function run_script() {
   local script
   eval "script=\${$1:-}"  # fetch value of variable passed in $1 (double indirection)
   if [ "${script// }" != "" ]; then  # only run when non-empty
      travis_run --title "$(colorize BOLD Running $1)" $script
      result=$?
      test $result -ne 0 && echo -e $(colorize RED "$1 failed with return value: $result. Aborting.") && exit 2
   fi
}

# work-around for https://github.com/moby/moby/issues/34096
# ensures that copied files are owned by the target user
function docker_cp {
  set -o pipefail
  tar --numeric-owner --owner="${docker_uid:-root}" --group="${docker_gid:-root}" -c -f - -C "$(dirname "$1")" "$(basename "$1")" | docker cp - "$2"
  set +o pipefail
}

function run_docker() {
   run_script BEFORE_DOCKER_SCRIPT

    # Choose the docker container to use
    if [ -n "${ROS_REPO:=}" ] && [ -n "${DOCKER_IMAGE:=}" ]; then
       echo -e $(colorize YELLOW "DOCKER_IMAGE=$DOCKER_IMAGE overrides ROS_REPO=$ROS_REPO setting")
    fi
    if [ -z "${DOCKER_IMAGE:=}" ]; then
       test -z "${ROS_DISTRO:-}" && echo -e $(colorize RED "ROS_DISTRO not defined: cannot infer docker image") && exit 2
       case "${ROS_REPO:-ros}" in
          ros) export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci ;;
          ros-shadow-fixed) export DOCKER_IMAGE=moveit/moveit:$ROS_DISTRO-ci-shadow-fixed ;;
          *) echo -e $(colorize RED "Unsupported ROS_REPO=$ROS_REPO. Use 'ros' or 'ros-shadow-fixed'"); exit 1 ;;
       esac
    fi

    echo -e $(colorize BOLD "Starting Docker image: $DOCKER_IMAGE")
    travis_run docker pull $DOCKER_IMAGE

    # Forward ssh agents
    local -a run_opts
    if [ "$SSH_AUTH_SOCK" ]; then
      local auth_dir
      auth_dir=$(dirname "$SSH_AUTH_SOCK")
      run_opts+=(-v "$auth_dir:$auth_dir" -e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
    fi
    
    local cid
    # Run travis.sh again, but now within Docker container
    cid=$(docker create \
        -e IN_DOCKER=1 \
        -e MOVEIT_CI_TRAVIS_TIMEOUT=$(travis_timeout $MOVEIT_CI_TRAVIS_TIMEOUT) \
        -e BEFORE_SCRIPT \
        -e CI_SOURCE_PATH=${CI_SOURCE_PATH:-/root/$REPOSITORY_NAME} \
        -e UPSTREAM_WORKSPACE \
        -e TRAVIS \
        -e TRAVIS_BRANCH \
        -e TRAVIS_PULL_REQUEST \
        -e TRAVIS_OS_NAME \
        -e TEST_PKG \
        -e TEST \
        -e TEST_BLACKLIST \
        -e WARNINGS_OK \
        -e ABI_BASE_URL \
        -e CC=${CC_FOR_BUILD:-${CC:-cc}} \
        -e CXX=${CXX_FOR_BUILD:-${CXX:-c++}} \
        -e CFLAGS \
        -e CXXFLAGS \
        -v $(pwd):/root/$REPOSITORY_NAME \
        -v ${CCACHE_DIR:-$HOME/.ccache}:/root/.ccache \
        -t \
        -w /root/$REPOSITORY_NAME \
        "${run_opts[@]}" \
        $DOCKER_IMAGE /root/$REPOSITORY_NAME/.moveit_ci/travis.sh)

    # detect user inside container
    local docker_image
    docker_image=$(docker inspect --format='{{.Config.Image}}' "$cid")
    docker_uid=$(docker run --rm "${run_opts[@]}" "$docker_image" id -u)
    docker_gid=$(docker run --rm "${run_opts[@]}" "$docker_image" id -g)
    # pass common credentials to container
    if [ -d "$HOME/.ssh" ]; then
      docker_cp "$HOME/.ssh" "$cid:/root/"
    fi

    docker start -a "$cid"

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
   travis_run --retry apt-get -qq update

   # Make sure the packages are up-to-date
   travis_run --retry apt-get -qq dist-upgrade
   # Install required packages (if not yet provided by docker container)
   travis_run --retry apt-get -qq install -y wget sudo python-catkin-tools xvfb mesa-utils ccache ssh

   # Install clang-format if needed
   [[ "${TEST:=}" == *clang-format* ]] && travis_run --retry apt-get -qq install -y clang-format-3.9
   # Install clang-tidy stuff if needed
   [[ "$TEST" == *clang-tidy* ]] && travis_run --retry apt-get -qq install -y clang-tidy-6.0 clang-6.0
   # run-clang-tidy is part of clang-tools in Bionic, but not in Xenial -> ignore failure
   [[ "$TEST" == *clang-tidy-fix* ]] && travis_run_true apt-get -qq install -y clang-tools-6.0
   # Install catkin_lint if needed
   if [[ "$TEST" == *catkin_lint* ]]; then
       travis_run --retry apt-get -qq install -y python-pip
       travis_run --retry pip install catkin_lint
   fi
   # Enable ccache
   export PATH=/usr/lib/ccache:$PATH

   # Setup rosdep - note: "rosdep init" is already setup in base ROS Docker image
   travis_run --retry rosdep update

   travis_fold end update
}

function run_early_tests() {
   # Check for different tests. clang-format and catkin_lint will trigger an early exit
   # EARLY_RESULT="" -> no early exit, EARLY_RESULT=0 -> early success, otherwise early failure
   local EARLY_RESULT=""
   for t in $(unify_list " ,;" "$TEST") ; do
      case "$t" in
         clang-format)
            (source ${MOVEIT_CI_DIR}/check_clang_format.sh) # run in subshell to not exit
            EARLY_RESULT=$(( ${EARLY_RESULT:-0} + $? ))
            ;;
         catkin_lint)
            (source ${MOVEIT_CI_DIR}/check_catkin_lint.sh) # run in subshell to not exit
            EARLY_RESULT=$(( ${EARLY_RESULT:-0} + $? ))
            ;;
         clang-tidy-check)  # run clang-tidy along with compiler and report warning
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_CXX_CLANG_TIDY=clang-tidy-6.0"
            ;;
         clang-tidy-fix)  # run clang-tidy -fix and report code changes in the end
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
            ;;
         abi)  # abi-checker requires debug symbols
            CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS_DEBUG=\"-g -Og\""
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
      echo "Adding $item"
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
                    wget -nv https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-tidy \
                         -O $CI_SOURCE_PATH/.clang-tidy
      travis_run --display "Applying the following clang-tidy checks:" cat $CI_SOURCE_PATH/.clang-tidy
   fi

   # run BEFORE_SCRIPT, which might modify the workspace further
   run_script BEFORE_SCRIPT

   # For debugging: list the files in workspace's source folder
   travis_run_simple cd $ROS_WS/src
   travis_run --title "List files in ROS workspace's source folder" ls --color=auto -alhF

   # Install source-based package dependencies
   travis_run --retry rosdep install -y -q -n --from-paths . --ignore-src --rosdistro $ROS_DISTRO

   # Change to base of workspace
   travis_run_simple cd $ROS_WS

   # Validate that we have some packages to build
   test -z "$(catkin list)" && echo -e "$(colorize RED Workspace $ROS_WS has no packages to build. Terminating.)" && exit 1
   travis_fold end ros.ws
}

function build_workspace() {
   echo -e $(colorize GREEN Building Workspace)
   # Configure catkin
   travis_run --title "catkin config $CMAKE_ARGS" catkin config --extend "${ROS_UNDERLAY:-/opt/ros/$ROS_DISTRO}" --install --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE="-O3" $CMAKE_ARGS --

   # Console output fix for: "WARNING: Could not encode unicode characters"
   export PYTHONIOENCODING=UTF-8

   # For a command that doesn’t produce output for more than 10 minutes, prefix it with travis_run_wait
   travis_run_wait 60 --title "catkin build" catkin build --no-status --summarize

   # Allow to verify ccache usage
   travis_run --title "ccache statistics" ccache -s
}

function test_workspace() {
   echo -e $(colorize GREEN Testing Workspace)

   local old_ustatus=${-//[^u]/}
   set +u  # disable checking for unbound variables for the next line
   travis_run_simple --title "Sourcing newly built install space" source install/setup.bash
   test -n "$old_ustatus" && set -u  # restore variable checking option

   # Consider TEST_BLACKLIST
   TEST_BLACKLIST=$(unify_list " ,;" ${TEST_BLACKLIST:-})
   echo -e $(colorize YELLOW Test blacklist: $(colorize THIN $TEST_BLACKLIST))
   test -n "$TEST_BLACKLIST" && catkin config --blacklist $TEST_BLACKLIST &> /dev/null

   # Also blacklist external packages
   all_pkgs=$(catkin_topological_order $ROS_WS --only-names 2> /dev/null)
   source_pkgs=$(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null)
   blacklist_pkgs=$(filter_out "$source_pkgs" "$all_pkgs")
   test -n "$blacklist_pkgs" && catkin config --append-args --blacklist $blacklist_pkgs &> /dev/null

   # Build tests
   travis_run_wait --title "catkin build tests" catkin build --no-status --summarize --make-args tests --
   # Run tests, suppressing the output (confuses Travis display?)
   travis_run_wait --title "catkin run_tests" "catkin build --catkin-make-args run_tests -- --no-status --summarize 2>/dev/null"

   # Show failed tests
   travis_fold start test.results "catkin_test_results"
   for file in $(catkin_test_results | grep "\.xml:" | cut -d ":" -f1); do
      travis_run --display "Test log of $file" cat $file
   done
   travis_fold end test.results

   # Show test results summary and throw error if necessary
   catkin_test_results || exit 2
}

###########################################################################################################
# main program

# This repository has some dummy catkin packages in folder test_pkgs, which are needed for unit testing only.
# To not clutter normal builds, we just create a CATKIN_IGNORE file in that folder.
# A unit test can be recognized from the presence of the environment variable $TEST_PKG (see unit_tests.sh)
if [ -z "${TEST_PKG:-}" ]; then
  touch ${MOVEIT_CI_DIR}/test_pkgs/CATKIN_IGNORE # not a unit test build
fi

# Re-run the script in a Docker container
if [ "${IN_DOCKER:-0}" != "1" ]; then run_docker; fi
echo -e $(colorize YELLOW "Testing branch '${TRAVIS_BRANCH:-}' of '${REPOSITORY_NAME:-}' on ROS '$ROS_DISTRO'")

# If we are here, we can assume we are inside a Docker container
echo "Inside Docker container"

export ROS_WS=${ROS_WS:-/root/ros_ws} # default location of ROS workspace, if not defined differently in docker container
CMAKE_ARGS=""

# Prepend current dir if path is not yet absolute
[[ "$MOVEIT_CI_DIR" != /* ]] && MOVEIT_CI_DIR=$PWD/$MOVEIT_CI_DIR
if [[ "${CI_SOURCE_PATH:=}" != /* ]] ; then
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
run_xvfb
prepare_ros_workspace
run_early_tests

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
