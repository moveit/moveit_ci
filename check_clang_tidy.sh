# Change to source directory.
pushd $CI_SOURCE_PATH > /dev/null

# Find run-clang-tidy script: Xenial and Bionic install them with different names
export RUN_CLANG_TIDY=$(ls -1 /usr/bin/run-clang-tidy* | head -1)


# Run clang-tidy for all packages in CI_SOURCE_PATH
SOURCE_PKGS=" $(catkin_topological_order $CI_SOURCE_PATH --only-names) "

echo -e "\033[33;1mRunning clang-tidy check\033[0m"
COUNTER=0
(
    for file in $(find $CATKIN_WS/build -name compile_commands.json) ; do
        # skip an external package
        PKG=$(basename $(dirname $file))
        [[ "$SOURCE_PKGS" =~ (^|[[:space:]])$PKG($|[[:space:]]) ]] && continue

        let "COUNTER += 1"
        travis_time_start clang-tidy.$COUNTER "Processing $PKG"
        # Pipe the very verbose output of clang-tidy to /dev/null
        $RUN_CLANG_TIDY -fix -p $(dirname $file) > /dev/null 2>&1
        travis_time_end
    done
) &
cmd_pid=$!  # main cmd PID

timeout=$(( $TRAVIS_GLOBAL_TIMEOUT - ($(date +%s) - $TRAVIS_GLOBAL_START_TIME) / 60 ))
# Use travis_jigger to generate some '.' outputs to convince Travis, we are not stuck.
travis_jigger $cmd_pid $timeout "clang-tidy" &
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
