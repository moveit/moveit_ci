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

# Author: Robert Haschke
# Perform ABI check, inspired by https://github.com/ros-industrial/industrial_ci

source $(dirname ${BASH_SOURCE:-$0})/util.sh
ABI_TMP_DIR=${ABI_TMP_DIR:-/tmp/abi}

function abi_install() {
	travis_fold start abi_check "Installing ABI checker and dependencies"
	travis_run sudo apt-get install -y -qq wget elfutils perl links

	mkdir -p "${ABI_TMP_DIR}"

	# abi-dumper requires universal ctags
	travis_run sudo apt-get install -y -qq autoconf pkg-config
	travis_run git clone --depth 1 https://github.com/universal-ctags/ctags.git $ABI_TMP_DIR/ctags
	travis_run --display "Build universal ctags" "(cd $ABI_TMP_DIR/ctags && ./autogen.sh && ./configure --prefix $ABI_TMP_DIR && make install)"
	export PATH=$ABI_TMP_DIR/bin:$PATH

	wget -q -O /tmp/abi_installer.pl https://raw.githubusercontent.com/lvc/installer/master/installer.pl
	perl /tmp/abi_installer.pl -install -prefix $ABI_TMP_DIR abi-compliance-checker
	perl /tmp/abi_installer.pl -install -prefix $ABI_TMP_DIR abi-dumper

	travis_fold end abi_check ""
}

function abi_dump() {
	local name=$1
	local lib=$2
	local lib_dirs=$3
	local include_dirs=$4
	local dump=$5
	travis_run abi-dumper "$lib" -ld-library-path "$lib_dirs" -lver $name -o "$dump" -public-headers "$include_dirs"
}

# abi_check new_lib_dir
function abi_check() {
	local new_lib_dir=$1
	local new_include_dir=$2
	local old_lib_dir=$3
	local old_include_dir=$4
	local broken=()

	mkdir -p "${ABI_TMP_DIR}/new"
	mkdir -p "${ABI_TMP_DIR}/reports"
	for lib in ${new_lib_dir}/*.so; do
		echo "$lib"
		local lib_name=$(basename "$lib" .so)
		# create new dump
		new_dump=${ABI_TMP_DIR}/new/${lib_name}.dump
		abi_dump new "$lib" "$new_lib_dir:/opt/ros/$ROS_DISTRO/lib" "$new_include_dir" "$new_dump"

		old_lib=$old_lib_dir/${lib_name}.so
		! [ -f "$old_lib" ] && echo "missing $old_lib" && continue
		old_dump=${old_lib_dir}/../dump/${lib_name}.dump
		# create old dump if not yet found in ${old_lib_dir}/dump
		if ! [ -f "$old_dump" ]; then
			mkdir -p "${ABI_TMP_DIR}/old"
			old_dump=${ABI_TMP_DIR}/old/${lib_name}.dump
			abi_dump old "$old_lib" "$old_lib_dir:/opt/ros/$ROS_DISTRO/lib" "$old_include_dir" "$old_dump"
		fi

		travis_run_true abi-compliance-checker -report-path "${ABI_TMP_DIR}/reports/$lib_name.html" \
			-l "$lib_name" -n "$new_dump" -o "$old_dump"
		result=$?
		case "$result" in
			0) ;;
			1) broken+=("$(basename \"$lib\")")
				travis_run_true links -dump "${ABI_TMP_DIR}/reports/$lib_name.html"
				;;
			*) return "$result"
		esac
	done
	if [ "${#broken[@]}" -gt 0 ]; then
		echo -e $(colorize YELLOW "Broken ABI libraries:\\n${broken[*]}")
		return 2
	fi
	return 0
}

# TODO: If ABI_BASE_URL is not provided, need to build from last tag/merge (as industrial_ci)
test -z "$ABI_BASE_URL" && echo -e $(colorize YELLOW "For ABI check, please specify ABI_BASE_URL variable") && exit 1

if [ "$ABI_BASE_URL" == "generate" ] ; then
	test "$TRAVIS" == true && abi_install
	mkdir -p "${ROS_WS}/install/dump"
	for lib in ${ROS_WS}/install/lib/*.so; do
		echo "$lib"
		lib_name=$(basename "$lib" .so)
		abi_dump old "$lib" "${ROS_WS}/install/lib:/opt/ros/$ROS_DISTRO/lib" "${ROS_WS}/install/include" \
					"${ROS_WS}/install/dump/${lib_name}.dump"
	done
elif [ "$TRAVIS_PULL_REQUEST" != false ]; then
	# For a pull request, actually perform the abi check
	test "$TRAVIS" == true && abi_install
	# fetch and extract old abi from $ABI_BASE_URL
	mkdir -p "${ABI_TMP_DIR}/old"
	travis_run --display "Download and extract base ABI" \
		"(cd ${ABI_TMP_DIR} && wget -c $ABI_BASE_URL && cd old && tar xf ../$(basename $ABI_BASE_URL))"
	travis_run abi_check \
			"${ROS_WS}/install/lib" "${ROS_WS}/install/include" \
			"${ABI_TMP_DIR}/old/lib" "${ABI_TMP_DIR}/old/include"
else
	# TODO: If this commit is a release, push the install folder to ABI_BASE_URL
	:
fi
