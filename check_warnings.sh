# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

packages_with_warnings() {
   SOURCE_PKGS=($(colcon list --topological-order --names-only --base-paths $CI_SOURCE_PATH 2> /dev/null))
   for pkg in ${SOURCE_PKGS[@]} ; do
      # Warnings manifest themselves with log files in logs folder
      log_file=$(find $ROS_WS/log/latest_build/$pkg -name "stderr.log" 2> /dev/null)
      # Check if the stderr.log file is not empty and add it to the list of warnings if it is
      # Print result
      if [ -s ${log_file} ]; then
         echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
         echo "  Test results for: $pkg"
         echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
         echo -e "- $(colorize YELLOW $(colorize THIN $pkg)): $log_file"
         echo ""
         cat $log_file
         echo ""
      fi
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
