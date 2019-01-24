# Change to source directory.
pushd $CI_SOURCE_PATH > /dev/null

# Find run-clang-tidy script: Xenial and Bionic install them with different names
export RUN_CLANG_TIDY=$(ls -1 /usr/bin/run-clang-tidy* | head -1)


# Run clang-tidy in all build folders containing a compile_commands.json file
# Pipe the very verbose output of clang-tidy to /dev/null
# Use travis_jigger to generate some '.' outputs to convince Travis, we are not stuck.
echo -e "\033[33;1mRunning clang-tidy check\033[0m"
COUNTER=0
(
	for file in $(find $CATKIN_WS/build -name compile_commands.json) ; do
		let "COUNTER += 1"
		travis_time_start clang-tidy.$COUNTER "Processing $(basename $(dirname $file))"
		$RUN_CLANG_TIDY -fix -p $(dirname $file) > /dev/null 2>&1
		travis_time_end
	done
) &
cmd_pid=$!  # main cmd PID

# Start jigger process, taking care of the timeout and '.' outputs
travis_jigger $cmd_pid 10 "clang-tidy" &
jigger_pid=$!

# Wait for main command to finish
wait $cmd_pid 2>/dev/null
# Stop travis_jigger in any case
kill $jigger_pid 2> /dev/null && wait $! 2> /dev/null


# Make sure no changes have occured in repo
if ! git diff-index --quiet HEAD --; then
    # changes
    echo -e "\033[31;1mclang-tidy test failed: The following changes are required to comply to rules:\033[0m"
    git --no-pager diff
    exit 1
fi

echo -e "\033[32;1mPassed clang-tidy check\033[0m"
popd > /dev/null
