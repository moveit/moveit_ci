# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

travis_fold start check.catkin_lint "Checking for issues reported by catkin_lint"

# Skip external packages
all_pkgs=$(catkin_topological_order $ROS_WS --only-names 2> /dev/null)
source_pkgs=$(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null)
skip_pkgs=$(filter_out "$source_pkgs" "$all_pkgs")
skip_args=$(for pkg in $skip_pkgs ; do echo -n "--skip-pkg $pkg "; done)

travis_run catkin_lint --version
travis_run --title "Running catkin_lint" catkin_lint $skip_args $ROS_WS
result=$?

# Finish fold before printing result summary
travis_fold end check.catkin_lint

if [ $result -eq 0 ] ; then
  echo -e $(colorize GREEN "No catkin_lint issues reported.")
else
  echo -e $(colorize YELLOW "catkin_lint reports errors. Please fix them!")
  exit 2
fi
