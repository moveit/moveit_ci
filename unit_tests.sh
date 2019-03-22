#!/bin/bash

#********************************************************************
# Software License Agreement (BSD License)
#
#  Copyright (c) 2018, Bielefeld University
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#   * Neither the name of Bielefeld University nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#********************************************************************/

# Author: Robert Haschke
# Desc: integration tests, running travish.sh for various configurations

export MOVEIT_CI_DIR=$(dirname $0)  # path to the directory running the current script
source ${MOVEIT_CI_DIR}/util.sh
source ${MOVEIT_CI_DIR}/test_util.sh

# run function tests first
(${MOVEIT_CI_DIR}/function_tests.sh)
ASSERT_TRUE "test $? == 0" $0:$LINENO "function tests failed"
PASSED=0 # reset count after ASSERT_TRUE

# set default environment
export ROS_WS=/tmp/ros_ws
export ROS_REPO=ros
export ROS_DISTRO=${ROS_DISTRO:-crystal}
export WARNINGS_OK=true

# dummy functions to skip updates with --no-updates functions
apt-get() {
	echo "Dummy apt-get $*"
}
rosdep() {
	echo "Dummy rosdep $*"
}

all_groups="sanity warnings clang-format clang-tidy-fix clang-tidy-check"
skip_groups="${SKIP:-}"
# process options
while true ; do
	case "$1" in
		--quiet|-q) QUIET=/dev/null ;;  # suppress bulk of test's stdout
		--no-docker) export IN_DOCKER=1 ;; # run without docker
		--no-updates) export -f apt-get; export -f rosdep ;;
		--skip) skip_groups="$skip_groups $2"; shift ;; # skip certain tests
		--help|-h) echo "$0 [--quiet | -q] [--no-docker] [--no-updates] tests ($all_groups)"; exit 0 ;;
		*) break;;
	esac
	shift
done
test_groups="$@"
test -z "$test_groups" && test_groups=$all_groups
test_groups=$(filter_out "$skip_groups" "$test_groups")
echo -e "$(colorize BOLD Configured unit tests:) $test_groups"

for group in $test_groups ; do
	case $group in
		sanity)
			run_test 0 $0:$LINENO "successful BEFORE_SCRIPT" TEST_PKG=valid \
				'BEFORE_SCRIPT="echo first && false; echo second > /dev/null; echo Testing on $ROS_DISTRO"'

			run_test 2 $0:$LINENO "failing BEFORE_SCRIPT" TEST_PKG=valid \
				'BEFORE_SCRIPT="echo \"Failing BEFORE_SCRIPT\"; return 1"'

			run_test 2 $0:$LINENO "missing rosinstall file" TEST_PKG=valid \
				'UPSTREAM_WORKSPACE="missing.rosinstall;travis.rosinstall"'

			run_test 1 $0:$LINENO "unknown TEST" TEST=invalid TEST_PKG=valid

			# TODO(mlautman): Decide if we should keep this test as an empty ros workspace doesn't
			# 				  seem to be an acutual issue
			run_test 1 $0:$LINENO "empty ROS workspace" TEST_PKG=valid 'BEFORE_SCRIPT="rm valid"'

			;;
		warnings)
			run_test 0 $0:$LINENO "'warnings' package with warnings allowed" TEST_PKG=warnings WARNINGS_OK=true
			run_test 1 $0:$LINENO "'warnings' package with warnings forbidden" TEST_PKG=warnings WARNINGS_OK=false
			run_test 0 $0:$LINENO "'valid' package with warnings forbidden" TEST_PKG=valid WARNINGS_OK=false
      ;;
		# TODO(mlautman): restore once ament_tidy has been setup for ROS2
    # catkin_lint)
			# run_test 0 $0:$LINENO "catkin_lint on 'valid' package" TEST_PKG=valid TEST=catkin_lint
			# run_test 0 $0:$LINENO "catkin_lint + clang-format on 'valid' package" TEST_PKG=valid 'TEST="catkin_lint clang-format"'
			# run_test 2 $0:$LINENO "catkin_lint on 'catkin_lint' package" TEST_PKG=catkin_lint TEST=catkin_lint
			# run_test 2 $0:$LINENO "catkin_lint + clang-format on 'catkin_lint' package" TEST_PKG=catkin_lint 'TEST="catkin_lint, clang-format"'
			# ;;
		clang-format)
			run_test 0 $0:$LINENO "clang-format on 'valid' package" TEST_PKG=valid TEST=clang-format
			run_test 2 $0:$LINENO "clang-format on 'clang_format' package" TEST_PKG=clang_format TEST=clang-format
			;;
		# TODO(mlautman): restore once ament_tidy has been setup for ROS2
		#  clang-tidy-fix)
			# run_test 0 $0:$LINENO "clang-tidy-fix on 'valid' package" TEST_PKG=valid TEST=clang-tidy-fix
			# run_test 1 $0:$LINENO "clang-tidy-fix on 'clang_tidy' package" TEST_PKG=clang_tidy TEST=clang-tidy-fix
			# ;;
		# clang-tidy-check)  # only supported for cmake >= 3.6
			# run_test 0 $0:$LINENO "clang-tidy-check on 'valid' package, warnings forbidden" TEST_PKG=valid TEST=clang-tidy-check WARNINGS_OK=false
			# run_test 1 $0:$LINENO "clang-tidy-check on 'clang_tidy' package, warnings forbidden" TEST_PKG=clang_tidy TEST=clang-tidy-check WARNINGS_OK=false
			# ;;
		*) echo -e $(colorize YELLOW "Unknown test group '$group'.")
			echo "Known groups are: $all_groups" ;;
	esac
done

test_summary
