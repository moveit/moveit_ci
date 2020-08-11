# Software License Agreement - BSD 3-Clause License
#
# Author:  Dave Coleman

travis_fold start clang.format "Running clang-format check"
travis_run_simple --display "cd to repository source: $CI_SOURCE_PATH" cd $CI_SOURCE_PATH

# Ensure that a .clang-format config file is present, if not download from MoveIt
if [ ! -f .clang-format ]; then
    travis_run --title "Fetching default clang-format config from MoveIt" \
        wget -nv "https://raw.githubusercontent.com/ros-planning/moveit/$ROS_DISTRO-devel/.clang-format"
fi

# To ignore current workspace changes (e.g. from Git LFS files), stage all current changes
git add -u .

# Run clang-format
if [ ! -x "${CLANG_FORMAT_EXECUTABLE:=$(which clang-format)}" ] ; then
  # Use clang-format by default, but fall back to the most recent clang-format-x.x available in /usr/bin otherwise
  CLANG_FORMAT_EXECUTABLE=$(ls -t1 /usr/bin/clang-format-[^d]* 2> /dev/null | head -1)

  # As long as clang-format is not yet available, try to install it from following list
  for alternative in clang-format-3.9 clang-format ; do
    test -x "$CLANG_FORMAT_EXECUTABLE" && break
    travis_run --no-assert apt-get -qq install -y $alternative
    CLANG_FORMAT_EXECUTABLE=$(ls -t1 /usr/bin/clang-format* 2> /dev/null | grep -v clang-format-diff | head -1)
  done
  if [ ! -x "$CLANG_FORMAT_EXECUTABLE" ] ; then
    echo -e $(colorize RED "clang-format is not available (and couldn't be installed).")
    exit 1
  fi
fi
cmd="find . -name '*.h' -or -name '*.hpp' -or -name '*.cpp' | xargs $CLANG_FORMAT_EXECUTABLE -i -style=file"
travis_run --display "Running clang-format${ANSI_RESET}\\n$cmd" "$cmd"

# Check for changes in repo
travis_have_fixes
result=$?

# Finish fold before printing result summary
travis_fold end clang.format

if [ $result -eq 1 ] ; then
  echo -e $(colorize GREEN "Passed clang-format check")
else
  echo -e $(colorize RED "clang-format check failed. Open fold for details.")
  echo -e "Run the following command to fix these issues:\\n$cmd"
  exit 2
fi
