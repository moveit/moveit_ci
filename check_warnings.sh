# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

packages_with_warnings() {
   for pkg in $(colcon info | grep 'name: ' | sed -e "s/.*name: //g" 2> /dev/null) ; do
      # Warnings manifest themselves log files in catkin tools' logs folder
      log_file=$(find $ROS_WS/log/latest_build/$pkg -name "stderr.log" 2> /dev/null)
      # Extract the stderr.log file
      # Print result
      if [ -s ${log_file} ]; then echo -e "- $(colorize YELLOW $(colorize THIN $pkg)): $log_file"; fi
   done
}

have_warnings=$(packages_with_warnings)
if [ -n "$have_warnings" ] ; then
   test "$WARNINGS_OK" == 1 && color=YELLOW || color=RED
   travis_run_simple --display "$(colorize $color The following packages have warnings in the shown build steps:)" "echo -e \"$have_warnings\""
   echo -e $(colorize BOLD "Please look into the build details and take the time to fix those issues.")
   # if warnings are not allowed, fail
   test "$WARNINGS_OK" == 0 && exit 2 || true
else
   echo -e $(colorize GREEN "No warnings. Great!")
fi
