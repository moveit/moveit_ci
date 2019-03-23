# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

packages_with_warnings() {
   SOURCE_PKGS=($(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null))
   for pkg in ${SOURCE_PKGS[@]} ; do
      # Warnings manifest themselves log files in catkin tools' logs folder
      files=$(find $ROS_WS/logs/$pkg -name "*build.cmake.000.log.stderr" -o -name "*build.make.00[01].log.stderr" 2> /dev/null)
      # Extract types of failures from file names
      issues=""
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.cmake\.000.*:cmake :p')"
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.make\.000.*:build :p')"
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.make\.001.*:test-build :p')"
      # Print result
      test -n "${files}" && echo -e "- $(colorize YELLOW $(colorize THIN $pkg)): $issues"
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
