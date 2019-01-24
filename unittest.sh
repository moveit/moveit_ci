#!/bin/bash

source util.sh

# save stdout as 3 and stderr as 4, then redirect stdout(1) to /dev/null and stderr(2) to 3(stdout)
exec 3>&1  4>&2  1>/dev/null  2>&3

function EXPECT_TRUE {
	local test_cmd=$1
	local location=$2
	local message=$3
	if ! eval $test_cmd ; then
		exec 1>&3  2>&4  # restore stdout + stderr
		echo -e "$location:\033[31;1m $test_cmd \033[0m $message"
		exit -1
	fi
}

# travis_run_impl should return the value of the (last) command
travis_run_impl true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Wrong result"

travis_run_impl false
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Wrong result"

travis_run_impl return 2
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Wrong result"

# several commands should be possible too, e.g. when passed into BEFORE_SCRIPT variable
cmds="echo; return 2"
travis_run_impl $cmds
EXPECT_TRUE "test $? -eq 2" $0:$LINENO "Wrong result"


# travis_run should continue on success
travis_run true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Wrong result"

# ... but exit on failure
(travis_run false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Wrong result"


# travis_run_wait should continue on success
travis_run_wait 10 true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Wrong result"

# ... but exit on failure
(travis_run_wait 10 false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Wrong result"


# first (numerical) argument to travis_run_wait is optional
travis_run_wait true
EXPECT_TRUE "test $? -eq 0" $0:$LINENO "Wrong result"

(travis_run_wait false)  # run in subshell to avoid exit from this script
EXPECT_TRUE "test $? -eq 1" $0:$LINENO "Wrong result"


exec 1>&3  2>&4  # restore stdout + stderr
echo -e "\033[32;1mSuccessfully passed unittest\033[0m"
