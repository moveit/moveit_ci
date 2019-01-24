# Install Dependencies
travis_run apt-get -qq install -y clang-format-3.9

# Change to source directory.
cd $CI_SOURCE_PATH

# This directory can have its own .clang-format config file but if not, MoveIt's will be provided
if [ ! -f .clang-format ]; then
    travis_run wget -nv "https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-format"
fi

# Run clang-format
travis_time_start moveit_ci.clang-format "Running clang-format"  # start fold
find . -name '*.h' -or -name '*.hpp' -or -name '*.cpp' | xargs clang-format-3.9 -i -style=file
travis_time_end  # end fold

# Make sure no changes have occured in repo
if ! git diff-index --quiet HEAD --; then
    # changes
    echo -e "\033[31;1mclang-format test failed: The following changes are required to comply to rules:\033[0m"
    git --no-pager diff
    exit 1 # error
fi

echo -e "\033[32;1mPassed clang-format check\033[0m"
