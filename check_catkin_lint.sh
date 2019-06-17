# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

travis_fold start check.catkin_lint "Checking for issues reported by catkin_lint"

travis_run catkin_lint --version
travis_run --title "Running catkin_lint in repository source: $CI_SOURCE_PATH" \
    catkin_lint $CI_SOURCE_PATH
result=$?

# Finish fold before printing result summary
travis_fold end check.catkin_lint ""

if [ $result -eq 0 ] ; then
  echo -e $(colorize GREEN "No catkin_lint issues reported.")
else
  echo -e $(colorize YELLOW "catkin_lint reports errors. Please fix them!")
  exit 2
fi
