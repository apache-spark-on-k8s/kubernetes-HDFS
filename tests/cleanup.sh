#!/usr/bin/env bash
# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch an error in command pipes. e.g. mysqldump fails (but gzip succeeds)
# in `mysqldump |gzip`
set -o pipefail
if [[ "${DEBUG:-}" = "true" ]]; then
# Turn on traces, useful while debugging but commented out by default
  set -o xtrace
fi

_MY_SCRIPT="${BASH_SOURCE[0]}"
_TEST_DIR=$(cd "$(dirname "$_MY_SCRIPT")" && pwd)

cd $_TEST_DIR
export PATH=${_TEST_DIR}/bin:$PATH

_DEFAULT_CASES="*"
: "${CASES:=$_DEFAULT_CASES}"
_CASES=$(ls ${_TEST_DIR}/cases/${CASES})
for _CASE in $_CASES; do
  source $_CASE
  echo Cleaning up test case: $_CASE
  cleanup_test_case
 done
