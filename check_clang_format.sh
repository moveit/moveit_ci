# Software License Agreement - BSD 3-Clause License
#
# Author:  Dave Coleman

travis_fold start clang.format "Running clang-format check"
travis_run_simple --display "cd to repository source: $CI_SOURCE_PATH" cd $CI_SOURCE_PATH

# Install Dependencies
travis_run apt-get -qq install -y clang-format-3.9

# Ensure that a .clang-format config file is present, if not download from MoveIt
if [ ! -f .clang-format ]; then
    travis_run --title "Fetching default clang-format config from MoveIt" \
        wget -nv "https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-format"
fi

# Run clang-format
cmd="find . -name '*.h' -or -name '*.hpp' -or -name '*.cpp' | xargs clang-format-3.9 -i -style=file"
travis_run --display "Running clang-format${ANSI_RESET}\\n$cmd" "$cmd"

# Check for changes in repo
travis_have_fixes
result=$?

# Finish fold before printing result summary
travis_fold end clang.format ""

if [ $result -eq 1 ] ; then
  echo -e $(colorize GREEN "Passed clang-format check")
else
  echo -e $(colorize RED "clang-format check failed. Open fold for details.")
  echo -e "Run the following command to fix these issues:\\n$cmd"
  exit 2
fi
