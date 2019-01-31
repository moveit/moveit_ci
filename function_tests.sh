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
# Desc: unit tests for travis_* functions in util.sh

source $(dirname ${BASH_SOURCE:-$0})/util.sh
source $(dirname ${BASH_SOURCE:-$0})/test_util.sh

echo -e $(colorize YELLOW THIN "Testing basic travis functions")

# Suppress normal Travis output: save stdout as 3, then redirect stdout(1) to /dev/null
exec 3>&1  1>/dev/null

function restore_stdout() {
	exec 1>&${STDOUT:-1}
	STDOUT=1
}
trap restore_stdout EXIT # automatically restore output when exiting

# validate EXPECT_TRUE
! EXPECT_TRUE "test 0 -eq 0" $0:$LINENO "" && echo -e "$(colorize RED EXPECT_TRUE reports an error for no reason)" && exit 2
EXPECT_TRUE "test 0 -eq 1" $0:$LINENO "" && echo -e "$(colorize RED EXPECT_TRUE missed an error)" && exit 2
# validate ASSERT_TRUE
! (ASSERT_TRUE "test 0 -eq 0" $0:$LINENO "") && echo -e "$(colorize RED ASSERT_TRUE reports an error for no reason)" && exit 2
(ASSERT_TRUE "test 0 -eq 1" $0:$LINENO "") && echo -e "$(colorize RED ASSERT_TRUE missed an error)" && exit 2

# enable really_echo() from here on
STDOUT=3

really_echo -e $(colorize GREEN $(colorize THIN "EXPECT_TRUE and ASSERT_TRUE work as expected. Let's start."))

# reset test counts (previous calls already generated 2 passes and 2 failures
PASSED=0
FAILED=0

# Testing strip_off_ansi_codes
output=$(strip_off_ansi_codes "${ANSI_RED}foo\\r\\t${ANSI_RESET}bar${ANSI_CLEAN}")
ASSERT_TRUE "test \"$output\" == \"foobar\"" $0:$LINENO "Should strip all ansi codes, tabs, and carriage return chars"


# signatures of start / end timing tag
TIMING_START="travis_time:start:[[:xdigit:]]+"
TIMING_END="travis_time:end:[[:xdigit:]]+:start=[[:digit:]]+,finish=[[:digit:]]+,duration=[[:digit:]]+"

# Testing travis_fold
output=$(strip_off_ansi_codes $(travis_fold start; travis_fold end))
EXPECT_TRUE "[[ \"$output\" =~ ^$(FOLDING_START)1$(FOLDING_END)1$ ]]" $0:$LINENO "fold tag generation fails"
output=$(strip_off_ansi_codes $(travis_fold start; travis_fold start))
EXPECT_TRUE "[[ \"$output\" =~ ^$(FOLDING_START)1$(FOLDING_START)2$ ]]" $0:$LINENO "Expecting number to increase"

output=$(strip_off_ansi_codes $(travis_fold start name; travis_fold end name))
EXPECT_TRUE "[[ \"$output\" =~ ^$(FOLDING_START name)1$(FOLDING_END name)1$ ]]" $0:$LINENO "fold tag generation fails"

output=$(travis_fold start name; travis_fold end other)
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Expecting failure due to mismatching fold names"
EXPECT_TRUE "[[ \"$(strip_off_ansi_codes $output)\" == *match* ]]" $0:$LINENO "Expecting error message mentioning mismatch"

output=$(travis_fold end other)
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Expecting failure due to missing start fold"
EXPECT_TRUE "[[ \"$(strip_off_ansi_codes $output)\" == *issing* ]]" $0:$LINENO "Expecting error message mentioning missing start"

output=$(strip_off_ansi_codes $(travis_fold start name message))
EXPECT_TRUE "[[ \"$output\" =~ ^$(FOLDING_START name)1message$ ]]" $0:$LINENO "For start action, message should be shown"

output=$(strip_off_ansi_codes $(travis_fold start name; travis_fold end name message))
EXPECT_TRUE "[[ \"$output\" =~ ^$(FOLDING_START name)1$(FOLDING_END name)1$ ]]" $0:$LINENO "For end action, message should be suppressed"


# Testing travis_timeout
output=$(travis_timeout)
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Expecting result 1, because no timeout parameter was given"
EXPECT_TRUE "test \"$output\" == \"20\"" $0:$LINENO "Expecting default timeout"

output=$(travis_timeout "foo")
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Expecting result 1, because no valid timeout was given"
EXPECT_TRUE "test \"$output\" == \"20\"" $0:$LINENO "Expecting default timeout"

output=$(travis_timeout 42)
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting result 0, because a valid timeout was given"
EXPECT_TRUE "test \"$output\" == \"42\"" $0:$LINENO "Expecting given timeout"

output=$(MOVEIT_CI_TRAVIS_TIMEOUT=0; travis_timeout 1)
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting result 0, because a valid timeout was given"
EXPECT_TRUE "test \"$output\" == \"0\"" $0:$LINENO "Expecting zero timeout"


# travis_run_impl should return the return value of the (last) command
travis_run_impl true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting success"

travis_run_impl false
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Expecting failure"
(travis_run_simple false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Expecting terminate"

travis_run_impl "(return 2)"
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Wrong result"
(travis_run_simple "(return 4)")  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Expecting terminate"

output=$(strip_off_ansi_codes $(var=bar; travis_run_impl --hide "echo -n foo; echo -n hidden &>/dev/null; echo -n $var"))
EXPECT_TRUE "test \"$output\" == \"foobar\"" $0:$LINENO "Expecting output from two echos"
output=$(strip_off_ansi_codes $(travis_run_impl --timing --display "message" "true"))
EXPECT_TRUE "[[ \"$output\" =~ ^${TIMING_START}message\ ${TIMING_END}$ ]]" $0:$LINENO "Invalid timing message"
output=$(strip_off_ansi_codes $(travis_run_impl --timing --display "message" "true; echo foo &>/dev/null"))
EXPECT_TRUE "[[ \"$output\" =~ ^${TIMING_START}message\ ${TIMING_END}$ ]]" $0:$LINENO "Unexpected cmd output"
output=$(strip_off_ansi_codes $(travis_run_impl true))
EXPECT_TRUE "test \"$output\" == \"true\"" $0:$LINENO "Expecting cmd to be echoed"
output=$(strip_off_ansi_codes $(travis_run_impl --hide true))
EXPECT_TRUE "test \"$output\" == \"\"" $0:$LINENO "--hide should suppress echo"
output=$(strip_off_ansi_codes $(travis_run_impl --display "me ss age" echo -n con tent))
EXPECT_TRUE "test \"$output\" == \"me ss age con tent\"" $0:$LINENO "Expecting custom message"

# travis_run should continue on success
travis_run true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting success"

# ... but exit on failure
(travis_run false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Expecting terminate"

# Validate multi-token commands with multi-token custom message
# signatures of start / end tokens
TOKEN_START="$(FOLDING_START)2${TIMING_START}"
TOKEN_END="${TIMING_END}$(FOLDING_END)2"
output=$(strip_off_ansi_codes $(travis_run --display "me ss age" echo con tent))
EXPECT_TRUE "[[ \"$output\" =~ ^${TOKEN_START}me\ ss\ age\ con\ tent\ ${TOKEN_END}$ ]]" $0:$LINENO "Expecting custom message"
output=$(strip_off_ansi_codes $(travis_run_true --display "me ss age" echo con tent))
EXPECT_TRUE "[[ \"$output\" =~ ^${TOKEN_START}me\ ss\ age\ con\ tent\ ${TOKEN_END}$ ]]" $0:$LINENO "Expecting custom message"
# Running $(travis_run_wait ...) as a subshell, sleeps for 60s in travis_monitor for no reason
#output=$(strip_off_ansi_codes $(travis_run_wait 10 --display "me ss age" echo con tent))
#EXPECT_TRUE "[[ \"$output\" =~ ^${TOKEN_START}me\ ss\ age\ con\ tent\ ${TOKEN_END}$ ]]" $0:$LINENO "Expecting custom message"

# Redirection needs to be embedded into the command
output=$(strip_off_ansi_codes $(travis_run --display "me ss age" "true; echo con tent > /dev/null; true"))
EXPECT_TRUE "[[ \"$output\" =~ ^${TOKEN_START}me\ ss\ age\ ${TOKEN_END}$ ]]" $0:$LINENO "Redirection not working"


# travis_run_wait should continue on success
travis_run_wait 10 true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting success"

# first (numerical) argument to travis_run_wait is optional
travis_run_wait true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Expecting success"

# On timeout, travis_run_wait should return with code 124
(travis_run_wait 0 sleep 100)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 124" $0:$LINENO "Expecting timeout"

# travis_run_wait should exit with code 2 on failure
(travis_run_wait 10 false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Expecting terminate"


# test filter
output=$(filter "t2 t4" $(echo t1 t2 t3 t4))
EXPECT_TRUE "test \"${output% *}\" == \"t2 t4\"" $0:$LINENO ""

output=$(filter "" "t1,t2,t3,t4")
EXPECT_TRUE "test \"${output% *}\" == \"\"" $0:$LINENO ""

output=$(filter "t1;" "t1;t2;t3;t4")
EXPECT_TRUE "test \"${output% *}\" == \"t1\"" $0:$LINENO ""

output=$(filter "missing" "t1;t2;t3;t4")
EXPECT_TRUE "test \"${output% *}\" == \"\"" $0:$LINENO ""

# test filter-out
output=$(filter-out "t2 t4" $(echo t1 t2 t3 t4))
EXPECT_TRUE "test \"${output% *}\" == \"t1 t3\"" $0:$LINENO ""

output=$(filter-out "" "t1,t2,t3,t4")
EXPECT_TRUE "test \"${output% *}\" == \"t1 t2 t3 t4\"" $0:$LINENO ""

output=$(filter-out "t1;" "t1;t2;t3;t4")
EXPECT_TRUE "test \"${output% *}\" == \"t2 t3 t4\"" $0:$LINENO ""

output=$(filter-out "missing" "t1;t2;t3;t4")
EXPECT_TRUE "test \"${output% *}\" == \"t1 t2 t3 t4\"" $0:$LINENO ""


# test unify_list
output=$(unify_list " ,;" "a,b;c d")
EXPECT_TRUE "test \"$output\" == \"a b c d\"" $0:$LINENO ""

output=$(unify_list "," "a,b;c d")
EXPECT_TRUE "test \"$output\" == \"a b;c d\"" $0:$LINENO ""


test_summary
