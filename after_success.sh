#!/bin/bash -u
# -*- indent-tabs-mode: nil  -*-

# Software License Agreement - BSD License
#
# This script runs after successful travis run
#
# Author:  Tyler Weaver

# Helper functions
source .travis/util.sh

if [[ "${TEST:=}" == *code-coverage* ]]; then
  echo -e $(colorize BOLD "Generating codecov.io report")
  travis_run --title "changing ownership of build products" sudo chown -R $USER:$USER build/
  travis_run --title "codecov.io report upload" bash <(curl -s https://codecov.io/bash)
fi
