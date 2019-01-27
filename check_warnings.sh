# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

packages_with_warnings() {
   for pkg in $(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null) ; do
      # Warnings manifest themselves log files in catkin tools' logs folder
      files=$(find $CATKIN_WS/logs/$pkg -name "*build.cmake.000.log.stderr" -o -name "*build.make.00[01].log.stderr" 2> /dev/null)
      # Extract types of failures from file names
      issues=""
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.cmake\.000.*:cmake :p')"
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.make\.000.*:build :p')"
      issues="${issues}$(echo $files | sed -ne 's:.*/build\.make\.001.*:test-build :p')"
      # Print result
      test -n "${files}" && echo -e "- ${ANSI_YELLOW}${ANSI_THIN}$pkg${ANSI_RESET}: $issues"
   done
}

have_warnings=$(packages_with_warnings)
if [ -n "$have_warnings" ] ; then
   travis_run_simple --display "${ANSI_YELLOW}The following packages have warnings in the shown build steps:${ANSI_RESET}" \
         "echo -e \"$have_warnings\""
   echo -e "${ANSI_BOLD}Please look for build details and take the time to fix them.${ANSI_RESET}"
   exit 42  # special error code for warnings
else   
   echo -e "${ANSI_GREEN}No warnings. Great!${ANSI_RESET}"
fi
