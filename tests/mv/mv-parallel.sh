#!/bin/sh
# test mv's -H and -L options

# Copyright (C) 2000-2026 Free Software Foundation, Inc.

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a move of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

. "${srcdir=.}/tests/init.sh"; path_prepend_ ./src

# Do a move and check the number of threads we spawned off.
#
# $1: Expected number of threads spawned
# $2..N: (optional) mv flags to pass (like "-j 4").
#
# Return 0 if mv spawned off the number of threads we expected and had no
# errors.  Return non-zero otherwise.
function do_mv {
  local expected=$1
  local rc=0
  shift

  cp -a src-dir _src-dir
  # grep strace lines to see how many threads spawned
  if ! spawned=$(strace -c -f mv $@ _src-dir dst-dir 2>&1 | \
    grep -E '^strace: Process [0-9]+ attached$' | wc -l) ; then
      # mv error
      rc=1
  fi

  if [ $spawned -ne $expected ] ; then
    rc=1
  fi

  # Verify contents of directories are the same
  diff -qr src-dir dst-dir || rc=1
  rm -fr dst-dir

  return $rc
}

nproc=$(nproc)
if [ $nproc -lt 2 ] ; then
  skip_ "test requires 2 or more MVUs"
fi

print_ver_ mv
uses_strace_

# Make our source directory and some files
mkdir src-dir || framework_failure_
for i in $(seq 1 $nproc) ; do
  echo f$i > src-dir/f$i || framework_failure_
done

# Verify we spawn off the number of expected threads we intend
do_mv 0 || fail=1
do_mv 0 "-j 0" || fail=1
do_mv 0 "--parallel 0" || fail=1
do_mv $nproc "-j $nproc" || fail=1
do_mv $nproc "--parallel $nproc" || fail=1
MV_NUM_THREADS=0 do_mv 0 || fail=1
MV_NUM_THREADS=$nproc do_mv $nproc "$args" || fail=1

# Verify -j|--parallel will override MV_NUM_THREADS
MV_NUM_THREADS=$nproc do_mv 0 "-j 0" || fail=1
MV_NUM_THREADS=$nproc do_mv 0 "--parallel 0" || fail=1

# Verify --debug disables multithreading
do_mv 0 "-j $nproc --debug" || fail=1

# Verify '-j|--parallel' fails with invalid or missing values
for arg in '-j' '--parallel' ; do
  returns_ 1 mv $arg src-dir dst-dir || fail=1
  returns_ 1 mv $arg helloworld src-dir dst-dir || fail=1
  returns_ 1 mv $arg -1 src-dir dst-dir || fail=1
done

# An invalid MV_NUM_THREADS should print a warning (but not fail) and
# default to 0 threads.
MV_NUM_THREADS=junk do_mv 0 || fail=1
cp -a src-dir _src-dir
MV_NUM_THREADS=junk mv _src-dir dst-dir 2>&1 | \
  grep "mv: warning: invalid MV_NUM_THREADS value 'junk'" > /dev/null || fail=1
rm -fr dst-dir

# If the user passes an invalid MV_NUM_THREADS with a valid -j|--parallel value,
# the parallel value should win, and not print a warning.
cp -a src-dir _src-dir
lines=$(MV_NUM_THREADS=junk mv -j $nproc _src-dir dst-dir 2>&1 | \
  wc -l) || fail=1
test $lines -eq 0 || fail=1
rm -fr dst-dir
MV_NUM_THREADS=junk do_mv $nproc "-j $nproc" || fail=1
MV_NUM_THREADS=junk do_mv 0 "-j 0" || fail=1

# Verify interactive mode disables multithreading
echo abc > src-dir/abc
spawned=$(yes | strace -c -f mv -j $nproc -i src-dir/abc dst-dir/def 2>&1 | \
  grep -E '^strace: Process [0-9]+ attached$' | wc -l) || fail=1
test $spawned -eq 0 || fail=1
rm -fr src-dir dst-dir

Exit $fail
