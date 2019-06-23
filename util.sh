# -*- indent-tabs-mode: nil  -*-
#********************************************************************
# Software License Agreement (BSD License)
#
#  Copyright (c) 2018, Bielefeld University
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#   * Neither the name of Bielefeld University nor the names of its
#     contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
#  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#********************************************************************/

# Author: Robert Haschke, Dave Coleman
# Desc: Utility functions to facilitate writing job scripts
# Strongly builds on corresponding bash utility functions of travis-ci:
# https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash

# source default functions, copied from travis-ci project
source $(dirname ${BASH_SOURCE:-$0})/travis_functions.sh

export ANSI_RED="\033[31m"
export ANSI_GREEN="\033[32m"
export ANSI_YELLOW="\033[33m"
export ANSI_BLUE="\033[34m"

export ANSI_THIN="\033[22m"
export ANSI_BOLD="\033[1m"

export ANSI_RESET="\033[0m"
export ANSI_CLEAR="\033[0K"

# set start time (if not yet done)
MOVEIT_CI_START_TIME=${MOVEIT_CI_START_TIME:-$(travis_nanoseconds)}

# Output the smaller one of the optional timeout parameter ($1) or the remaining time (in minutes)
# Return 0 if optional timeout parameter was consumed (looking like an integer), 1 if not
# This allows to compute the actual timeout in functions like this:
#   timeout=$(travis_timeout "$1") && shift
travis_timeout() {
  local timeout result remaining
  if [[ "${timeout:=${1:-}}" =~ ^[0-9]+$ ]] ; then
    result=0  # $1 looks like integer that should be consumed as a parameter
  else
    result=1  # parameter shouldn't be consumed
    timeout=20  # default timeout
  fi

  # remaining time in minutes (default timeout for open-source Travis jobs is 50min)
  remaining=$(( ${MOVEIT_CI_TRAVIS_TIMEOUT:-50} - ($(travis_nanoseconds) - $MOVEIT_CI_START_TIME) / 60000000000 ))
  # limit timeout to remaining time
  if [ $remaining -le $timeout ] ; then timeout=$remaining; fi
  echo "${timeout}"
  return $result
}

# travis_fold (start|end) [name] [message]
travis_fold() {
  # option -g declares those arrays globally!
  declare -ag _TRAVIS_FOLD_NAME_STACK  # "stack" array to hold name hierarchy
  declare -Ag _TRAVIS_FOLD_COUNTERS  # associated array to hold global counters

  local action="$1"
  local name="${2:-moveit_ci}"  # name defaults to moveit_ci
  name="${name/ /.}"  # replace spaces with dots in name
  local message="${3:-}"
  test -n "$message" && message="$(colorize BLUE BOLD $3)\\n"  # print message in bold blue by default

  set +u  # disable checking for unbound variables for the next line
  local length=${#_TRAVIS_FOLD_NAME_STACK[@]}
  set -u
  if [ "$action" == "start" ] ; then
    # push name to stack
    _TRAVIS_FOLD_NAME_STACK[$length]=$name
    # increment (or initialize) matching counter
    let "_TRAVIS_FOLD_COUNTERS[$name]=${_TRAVIS_FOLD_COUNTERS[$name]:=0} + 1"
  else
    action="end"
    message=""  # only start action may have a message
    # pop name from stack
    let "length -= 1"
    test $length -lt 0 && \
       echo -e "Missing travis_fold start before travis_fold end $name" && exit 1
    test "${_TRAVIS_FOLD_NAME_STACK[$length]}" != "$name" && \
       echo "'travis_fold end $name' not matching to previous travis_fold start ${_TRAVIS_FOLD_NAME_STACK[$length]}" && exit 1
    unset '_TRAVIS_FOLD_NAME_STACK[$length]'
  fi
  # actually generate the fold tag for travis
  echo -en "travis_fold:${action}:${name}.${_TRAVIS_FOLD_COUNTERS[$name]}\\r${ANSI_CLEAR}${message}"
}


# Run a command in Travis with nice folding display, timing, timeout etc.
# adapted from travis_cmd.bash
# Return values:
# - on success: 0
# - on failure: 2 if --assert option was given, otherwise return value of process
# - on timeout: 124 (return value of timeout command)
travis_run_impl() {
  local assert hide title display timing timeout cmd result trial=1 trials=1

  while true; do
    case "${1}" in
    --assert)  # terminate on failure?
      assert=true
      ;;
    --no-assert)  # terminate on failure?
      unset assert
      ;;
    --hide)  # hide cmd/display?
      hide=true
      ;;
    --show)  # hide cmd/display?
      unset hide
      ;;
    --title)  # use custom message as title, but keep command output
      title="${2}\\n"  # add newline, such that command output will go to next line
      unset hide  # implicitly enable output
      shift
      ;;
    --display)  # use custom message instead of command output
      display="${2}"
      unset hide  # implicitly enable output
      shift
      ;;
    --timing)  # enable timing?
      timing=true
      ;;
    --no-timing)  # enable timing?
      unset timing
      ;;
    --timeout)  # abort commands after a timeout
      timeout="${2}"
      shift
      ;;
    --no-timeout)  # disable (a previously set) timeout
      unset timeout
      ;;
    --trials)
      trials="${2}"
      shift
      ;;
    --retry)
      trials=3
      ;;
    *) break ;;
    esac
    shift
  done

  cmds="$*"
  export TRAVIS_CMD="${cmds}"

  if [ -n "${timing:-}" ]; then
    travis_time_start
  fi

  if [ -z "${hide:-}" ]; then
    echo -e "$(colorize BLUE THIN ${title:-}${display:-${cmds}})"
  fi

while [ "${trial}" -le "${trials}" ] ; do
  # Actually run cmds
  if [ -n "${timeout:-}" ]; then
    (eval "${cmds}") & # run cmds in subshell in background
    travis_wait $! $timeout "$cmds" # wait for the subshell process to finish
    result="${?}"
    if [ $result -eq 124 ] ; then
       echo -e "The command \"${TRAVIS_CMD}\" reached the $(colorize YELLOW internal $(colorize BOLD timeout) of ${timeout} minutes. Aborting.)\\n"
       exit 124
    fi
  else
    eval "${cmds}"
    result="${?}"
  fi

  if [ "${result}" -ne 0 ] && [ "${trials}" -ne 1 ] ; then
     echo -e $(colorize YELLOW "The command \"${TRAVIS_CMD}\" failed [trial ${trial} of ${trials}].")
     trial="$((trial + 1))"
     sleep 1
  else
     break
  fi
done

  if [ -n "${timing}" ]; then
    travis_time_finish
  fi

  # When asserting success, but we got a failure (and not a timeout (124)), terminate
  if [ -n "${assert:-}" -a $result -ne 0 -a $result -ne 124 ]; then
    echo -e $(colorize RED "The command \"${TRAVIS_CMD}\" $(colorize BOLD failed with error code ${result}).\\n")
    exit  2
#    travis_terminate 2
  fi

  return "${result}"
}

# Run command(s) with timing, but without folding
travis_run_simple() {
  travis_run_impl --timing --assert "$@"
}

# Run command(s) with folding and timing, ignoring failure
travis_run_true() {
  travis_fold start
    travis_run_simple --no-assert "$@"
    local result=$?
  travis_fold end
  return $result
}

# Run command(s) with timing, folding, and terminate on failure
travis_run() {
  # add option --assert to travis_run_true
  travis_run_true --assert "$@"
}

# Run command(s) with a timeout (of 20min by default)
travis_run_wait() {
  # parse first parameter as timeout and drop it if successful
  local timeout
  timeout=$(travis_timeout "$1") && shift
  travis_run_true --assert --timeout "${timeout}" "$@"
}

# Wait for the passed process to finish
# Adapted from travis_wait.bash
travis_wait() {
  local cmd_pid=$1  # we are waiting for this process to finish
  local timeout=$2  # timeout in mins

  travis_monitor $cmd_pid $timeout & # start monitoring process in background
  local monitor_pid=$!

  # Wait for main command to finish
  wait $cmd_pid 2>/dev/null
  local result=$?  # result of the main process

  if ! ps -p $monitor_pid &>/dev/null ; then
    # If monitor process is not running anymore, we timed out
    result=124
  else
    # kill monitor process
    kill $monitor_pid 2> /dev/null && wait $! 2> /dev/null
    # https://stackoverflow.com/questions/81520/how-to-suppress-terminated-message-after-killing-in-bash
  fi

  return $result  # return result of main process
}

# adapted from travis_jigger.bash
travis_monitor() {
  local cmd_pid=$1  # we are waiting for this process to finish
  local timeout=$(($2 * 60))  # timeout in secs
  local elapsed=0   # elapsed time in secs
  while [ "${elapsed}" -lt "${timeout}" ]; do
     for s in "/" "-" "\\" "|"; do
        echo -ne "$s \\r"
        let "elapsed += 1"
        sleep 1 # wait 1s
     done
  done

  kill -9 $cmd_pid  # kill monitored process
}

# Check repository for changes, return success(0) if there are changes
travis_have_fixes() {
  if ! git diff --quiet . ; then  # check for changes in current dir
    echo -e $(colorize RED "\\nThe following issues were detected:")
    git --no-pager diff .
    git checkout . # undo changes in current dir
    return 0
  fi
  return 1
}

# $(filter "PATTERN" "TEXT")
# Returns all words in TEXT that *do* match any of the PATTERN words,
# removing any words that *do not* match.
# words can be separated by space, comma, semicolon or newline
filter() {
  local PATTERN="$1"; shift
  # convert input lists into newline-separate lists: | tr ' ;,' '\n'
  # perform filtering: grep -Fvxf
  # and convert newlines back to spaces: | tr '\n' ' '
  echo "$*" | tr ' ;,' '\n' | grep -Fxf <(echo "$PATTERN" | tr ' ;,' '\n') | tr '\n' ' '
}

# $(filter_out "PATTERN" "TEXT")
# Returns all words in TEXT that *do not* match any of the PATTERN words,
# removing the words that *do match* one or more.
# This is the exact opposite of the filter function.
# words can be separated by space, comma, semicolon or newline
filter_out() {
  local PATTERN="$1"; shift
  # convert input lists into newline-separate lists: | tr ' ;,' '\n'
  # perform filtering: grep -Fvxf
  # and convert newlines back to spaces: | tr '\n' ' '
  echo "$*" | tr ' ;,' '\n' | grep -Fvxf <(echo "$PATTERN" | tr ' ;,' '\n') | tr '\n' ' '
}

# unify_list SEPARATORS LIST
# replace all separator chars given as first argument with spaces
unify_list() {
  local separators=$1; shift
  echo "$*" | tr "$separators" ' '
}

# usage: echo -e $(colorize RED Some ${fancy} text.)
function colorize() {
   local color reset
   while true ; do
      case "${1:-}" in
         RED|GREEN|YELLOW|BLUE)
            color="ANSI_$1"; eval "color=\$$color"; reset="${ANSI_RESET}" ;;
         THIN)
            color="${color:-}${ANSI_THIN}" ;;
         BOLD)
            color="${color:-}${ANSI_BOLD}"; reset="${reset:-${ANSI_THIN}}" ;;
         *) break ;;
      esac
      shift
   done
   echo -e "${color:-}$@${reset:-}"
}

# collect files that are modified since commit
function collect_modified_files() {
  local -n __modified_files=$1     # -n to modify argument by reference
  local filter=$2
  local src_dir=${3:-$PWD}
  local base=${4:-$TRAVIS_BRANCH}

  # Find top-level git folder of src_dir
  local strip_prefix=$(cd "$src_dir"; git rev-parse --show-toplevel)
  # Strip git folder from src_dir to keep relative path from git root to source files as stip_prefix
  strip_prefix="${src_dir#$strip_prefix/}"
  while IFS='' read -r line ; do
    # Add modified or added files to array - only using the relative path from src_dir, i.e. removing strip_prefix
    __modified_files+=("${line#$strip_prefix/}")
  done < <(git diff --name-only --diff-filter=MA "$base"..HEAD "$src_dir" | grep "$filter")
}
