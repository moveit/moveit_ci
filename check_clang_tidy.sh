# Change to source directory.
pushd $CI_SOURCE_PATH

# This directory can have its own .clang-tidy config file but if not, MoveIt's will be provided
if [ ! -f .clang-tidy ]; then
    wget "https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-tidy"
fi

# Find run-clang-tidy script: Xenial and Bionic install them with different names
export RUN_CLANG_TIDY=$(ls -1 /usr/bin/run-clang-tidy* | head -1)

# Run clang-tidy in all build folders containing a compile_commands.json file
# Pipe the very verbose output of clang-tidy to /dev/null
echo "Running clang-tidy"

travis_run_wait 60 find $CATKIN_WS/build -name compile_commands.json -exec \
    sh -c 'echo "Processing $(basename $(dirname {}))"; $RUN_CLANG_TIDY -fix -format -p $(dirname {}) > /dev/null 2>&1' \;

echo "Showing changes in code:"
git --no-pager diff

# Make sure no changes have occured in repo
if ! git diff-index --quiet HEAD --; then
    # changes
    echo "clang-tidy test failed: changes required to comply to rules. See diff above."
    exit 1
fi

echo "Passed clang-tidy check"
popd
