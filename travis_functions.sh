# copied from https://github.com/travis-ci/travis-build/blob/master/lib/travis/build/bash
#
# MIT LICENSE

# Copyright (c) 2018 Travis CI GmbH <contact+travis-build@travis-ci.org>

# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

travis_nanoseconds() {
  local cmd='date'
  local format='+%s%N'

  if hash gdate >/dev/null 2>&1; then
    cmd='gdate'
  elif [[ "${TRAVIS_OS_NAME}" == osx ]]; then
    format='+%s000000000'
  fi

  if [[ "${TRAVIS_OS_NAME}" == osx ]]; then
    format='+%s000000000'
  fi

  "${cmd}" -u "${format}"
}
travis_time_start() {
  TRAVIS_TIMER_ID="$(printf %08x $((RANDOM * RANDOM)))"
  TRAVIS_TIMER_START_TIME="$(travis_nanoseconds)"
  export TRAVIS_TIMER_ID TRAVIS_TIMER_START_TIME
  echo -en "travis_time:start:$TRAVIS_TIMER_ID\\r${ANSI_CLEAR}"
}
travis_time_finish() {
  local result="${?}"
  local travis_timer_end_time
  travis_timer_end_time="$(travis_nanoseconds)"
  local duration
  duration="$((travis_timer_end_time - TRAVIS_TIMER_START_TIME))"
  echo -en "travis_time:end:${TRAVIS_TIMER_ID}:start=${TRAVIS_TIMER_START_TIME},finish=${travis_timer_end_time},duration=${duration}\\r${ANSI_CLEAR}"
  return "${result}"
}
