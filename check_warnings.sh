# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD 3-Clause License
#
# Author:  Robert Haschke
# Desc: Check for warnings during build process of repo $CI_SOURCE_PATH

packages_with_warnings() {
   SOURCE_PKGS=($(colcon list --topological-order --names-only --base-paths $CI_SOURCE_PATH 2> /dev/null))
   for pkg in ${SOURCE_PKGS[@]} ; do
      # Warnings manifest themselves with a non-empty stderr.log file in colcon's log folder
      log_file=$ROS_WS/log/latest_build/$pkg/stderr.log
      test -s "$log_file" && echo -e "- $(colorize YELLOW $(colorize THIN $pkg))"
   done
}

have_warnings=$(packages_with_warnings)
if [ -n "$have_warnings" ] ; then
   test "$WARNINGS_OK" == 1 && color=YELLOW || color=RED
   travis_run_simple --display "$(colorize $color The following packages have warnings:)" "echo -e \"$have_warnings\""
   echo -e $(colorize BOLD "Please look into the build details and take the time to fix those issues.")
   # if warnings are not allowed, fail
   test "$WARNINGS_OK" == 0 && exit 2 || true
else
   echo -e $(colorize GREEN "No warnings. Great!")
fi
