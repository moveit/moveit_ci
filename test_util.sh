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
# Desc: utility functions for unit testing in bash

PASSED=0
FAILED=0

# allow to write to stdout despite redirection to $STDOUT
function really_echo() {
	1>&${STDOUT:-1} echo "$@"
}

function EXPECT_TRUE {
	local test_cmd=$1
	local location=$2
	local message="$3 "
	local type=${4:-"Expectation"}
	if ! eval $test_cmd ; then
		really_echo -e "$(colorize RED ${type} failed: $(colorize BOLD ${test_cmd}))\\n${message# }($location)"
		let "FAILED += 1"
		return 1
	else
		let "PASSED += 1"
	fi
}
function ASSERT_TRUE {
	if ! EXPECT_TRUE "$@" "Assertion"; then
		really_echo -e $(colorize RED BOLD Terminating.)
		exit 2
	fi
}
function strip_off_ansi_codes {
	echo -e $* | sed -e 's:\x1B\[[0-9;]*[mK]::g' -e 's:[[:cntrl:]]::g'
}

# signatures of start / end timing tag
TIMING_START="travis_time:start:[[:xdigit:]]+"
TIMING_END="travis_time:end:[[:xdigit:]]+:start=[[:digit:]]+,finish=[[:digit:]]+,duration=[[:digit:]]+"
# signatures of start / end folding tag given a specific fold name
function FOLDING_START() {
	echo "travis_fold:start:${1:-moveit_ci}\."
}
function FOLDING_END() {
	echo "travis_fold:end:${1:-moveit_ci}\."
}

function test_summary() {
	ALL=$(($PASSED + $FAILED))
	if [ $FAILED -ne 0 ] ; then
		really_echo -e $(colorize RED $(colorize BOLD $FAILED) out of $ALL tests failed. $(colorize BOLD Terminating).)
		exit 2
	else
		really_echo -e $(colorize GREEN $(colorize THIN Successfully passed all $ALL tests))
	fi
}

# utility function to run travis.sh as a unit test
# args: $1: expected result
#       $2: file location, should be $0:$LINENO
#       $3: informative test description
#       remaining args describe test environment varialbes, one per item
function run_test() {
	local expected="$1"; shift     # expected result
	local location="$1"; shift     # file location, $0:$LINENO
	local description="$1"; shift  # descriptive text
	local PRETTY_PRINT="s#^[^=]*#\x1B[1m&\x1B[0m#g" # regex to highlight variable name
	local squote=$(colorize YELLOW BOLD \')
	local dquote=$(colorize YELLOW BOLD \")
	local escape=$(colorize YELLOW BOLD \\\")
	local comment

	travis_fold start unittest "$(colorize YELLOW Running test:) $description"
	travis_run_true --title "Create ROS workspace" mkdir "$ROS_WS"
	( # Run actual test in sub shell
		echo -e $(colorize BOLD "Test environment:")
		# pretty print and setup test environment, highlighting the variable name
		for item in "$@" ; do
			echo -e "  $(echo $item | sed $PRETTY_PRINT)"
			if ! eval "export $item" ; then
				echo -en "$(colorize RED Failed to setup test environment.) "
				echo -en "Check that quoting of\\n$(echo $item | sed $PRETTY_PRINT)\\nfollows the scheme: "
				echo -e  "${squote}VARIABLE=${dquote}some ${escape}escaped${escape} content${dquote}${squote}"
				exit 255
			fi
		done
		# custom source path to test
		export CI_SOURCE_PATH=test_pkgs/$TEST_PKG
		echo -e "  $(echo "CI_SOURCE_PATH=$CI_SOURCE_PATH" | sed $PRETTY_PRINT)"
		# TEST_PKG indicates a unit test!
		export TEST_PKG
		export CXX=${CXX:-c++}

		# finally run travis.sh script
		source ${MOVEIT_CI_DIR}/travis.sh >&${QUIET:-1}
	)
	result=$?
	travis_run_true --title "Remove ROS workspace" rm -r "$ROS_WS"
	travis_fold end unittest # close fold before reporting error

	if [ $result -ne $expected ] ; then
		let "FAILED += 1"
		test $expected -eq 0 && comment="Expected success, but failed ($result)." || comment="Expected failure ($expected), but got $result"
		echo -e $(colorize RED "Test '$description' failed: $comment")
	else
		let "PASSED += 1"
		test $expected -eq 0 && comment="passed successfully, as expected" || comment=" failed ($result) as expected."
		echo -e $(colorize GREEN "Test '$description' $comment")
	fi
	echo
	return $result
}
