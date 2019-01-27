travis_fold start clang.tidy "Running clang-tidy check"
travis_run_impl --display "cd to repository source: $CI_SOURCE_PATH" cd $CI_SOURCE_PATH

# Find run-clang-tidy script: Xenial and Bionic install them with different names
export RUN_CLANG_TIDY=$(ls -1 /usr/bin/run-clang-tidy* | head -1)

# Run clang-tidy for all packages in CI_SOURCE_PATH
SOURCE_PKGS=$(catkin_topological_order $CI_SOURCE_PATH --only-names 2> /dev/null)

TAINTED_PKGS=""
COUNTER=0
(
    for file in $(find $CATKIN_WS/build -name compile_commands.json) ; do
        # skip an external package
        PKG=$(basename $(dirname $file))
        [[ "$SOURCE_PKGS" =~ (^|[[:space:]])$PKG($|[[:space:]]) ]] && continue

        let "COUNTER += 1"
        travis_fold start clang.tidy.$COUNTER "${ANSI_THIN}Processing $PKG"

        cmd="$RUN_CLANG_TIDY -fix -p $(dirname $file)"
        # Suppress the very verbose output of clang-tidy!
        travis_run_impl --timing --display "$cmd" "$cmd > /dev/null 2>&1"
        travis_have_fixes && TAINTED_PKGS="$TAINTED_PKGS\\n$PKG"
        travis_fold end clang.tidy.$COUNTER
    done
) &  # run in background to allow timeout monitoring
travis_wait $! $(travis_timeout)

# Finish fold before printing result summary
travis_fold end clang.tidy

if [ -z "$TAINTED_PKGS" ] ; then
  echo -e "${ANSI_GREEN}Passed clang-tidy check${ANSI_RESET}"
else
  echo -e "${ANSI_RED}clang-tidy check failed for the following packages:\\n${ANSI_RESET}$TAINTED_PKGS"
  exit 2
fi
