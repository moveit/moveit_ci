# Software License Agreement - BSD License
#
# Author:  Robert Haschke

_travis_run_clang_tidy_fix() {
    local SOURCE_PKGS COMPILED_PKGS counter pkg file
    SOURCE_PKGS=($(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null))

    # filter repository packages for those which have a compile_commands.json file in their build folder
    declare -A PKGS  # associative array
    for pkg in ${SOURCE_PKGS[@]} ; do
        file="$CATKIN_WS/build/$pkg/compile_commands.json"
        test -r "$file" && PKGS[$pkg]=$(dirname "$file")
    done

    for pkg in ${SOURCE_PKGS[@]} ; do  # process files in topological order
        test -z "${PKGS[$pkg]}" && continue  # skip pkgs without compile_commands.json
        travis_run_wait --title "  - ${ANSI_BLUE}Processing $pkg${ANSI_RESET}" \
            "$RUN_CLANG_TIDY_EXECUTABLE -fix -p ${PKGS[$pkg]} &> /dev/null"
        # if there are workspace changes, print broken pkg to file descriptor 3
        travis_have_fixes && 1>&3 echo $pkg || true  # should always succeed ;-)
    done
}

travis_fold start clang.tidy "Running clang-tidy check"
travis_run_simple --display "- cd to repository source: $CI_SOURCE_PATH" cd $CI_SOURCE_PATH

# Find run-clang-tidy script: Xenial and Bionic install them with different names
RUN_CLANG_TIDY_EXECUTABLE=$(ls -1 /usr/bin/run-clang-tidy* | head -1)
test -z "$RUN_CLANG_TIDY_EXECUTABLE" && \
   echo -e "${ANSI_YELLOW}${ANSI_THIN}Missing run-clang-tidy. Aborting.${ANSI_RESET}" && \
   exit 2
# Check whether -quiet options is supported
test ! $RUN_CLANG_TIDY_EXECUTABLE -quiet 2>&1 | grep -- "-quiet" > /dev/null && RUN_CLANG_TIDY_EXECUTABLE="$RUN_CLANG_TIDY_EXECUTABLE -quiet"

# Run _travis_run_clang_tidy_fix() and redirect file descriptor 3 to /tmp/clang-tidy.tainted to collect tainted pkgs
3>/tmp/clang-tidy.tainted travis_run_simple --display "- run-clang-tidy for all source packages" _travis_run_clang_tidy_fix
result=$?
test $result -ne 0 && exit $result

# Read content of /tmp/clang-tidy.tainted into variable TAINTED_PKGS
TAINTED_PKGS=$(< /tmp/clang-tidy.tainted)

# Finish fold before printing result summary
travis_fold end clang.tidy

if [ -z "$TAINTED_PKGS" ] ; then
  echo -e "${ANSI_GREEN}Passed clang-tidy check${ANSI_RESET}"
else
  echo -e "${ANSI_RED}clang-tidy check failed for the following packages:\\n${ANSI_YELLOW}${ANSI_THIN}$TAINTED_PKGS${ANSI_RESET}"
  exit 2
fi
