#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
test_name="${1:-}"

case "${test_name}" in
  ex1|ex2|ex3|ex4|ex5|ex6|ex7|ex8|ex9) ;;
  *)
    printf 'Usage: %s ex1|ex2|ex3|ex4|ex5|ex6|ex7|ex8|ex9\n' "$0" >&2
    exit 2
    ;;
esac

source_dir="${project_root}/for_test_obj/${test_name}_obj"
target_dir="${project_root}/cdp_ede_local-master/mycpu_env/func/obj"

for image in inst_ram.mif data_ram.mif; do
  if [[ ! -f "${source_dir}/${image}" ]]; then
    printf 'Missing test image: %s\n' "${source_dir}/${image}" >&2
    exit 1
  fi
done

mkdir -p "${target_dir}"
cp "${source_dir}/inst_ram.mif" "${target_dir}/inst_ram.mif"
cp "${source_dir}/data_ram.mif" "${target_dir}/data_ram.mif"

printf 'Selected %s -> %s\n' "${test_name}" "${target_dir}"
