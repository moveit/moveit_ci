# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Run ament linters for packages in $CI_SOURCE_PATH

# ament provides several basic linters: https://github.com/ament/ament_lint
# Documentation is poor and scattered. For now, we only run the cmake linter
# Something similar to catkin_lint doesn't seem to exist yet

travis_fold start check.ament_lint "Checking for issues reported by ament_lint"

travis_run --title "Running ament_lint_cmake in repository source: $CI_SOURCE_PATH" \
    ament_lint_cmake $CI_SOURCE_PATH
result=$?

# Finish fold before printing result summary
travis_fold end check.ament_lint

if [ $result -eq 0 ] ; then
  echo -e $(colorize GREEN "No linter issues reported.")
else
  echo -e $(colorize YELLOW "ament_lint reports errors. Please fix them!")
  exit 2
fi
