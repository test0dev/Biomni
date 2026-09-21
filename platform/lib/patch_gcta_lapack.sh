#!/usr/bin/env bash
# Ubuntu lapack.h appends a hidden Fortran string-length argument.
# GCTA's aarch64 calls predate that ABI. Idempotent.
set -euo pipefail
root="$(cd "$(dirname "$0")/../biomni_tools/src/gcta" && pwd)"
perl -pi -e 's/(dpotrf_|dpotri_)\(([^;]+)\)/$1($2, (size_t)1)/ if !/size_t/' \
  "$root/include/Matrix.hpp" "$root/main/mkl.cpp"
perl -0777 -pi -e 's/dormqr_\(\s*&side,\s*&t,\s*&n,\s*&n,\s*&n,\s*X,\s*&lda,\s*tau,\s*c,\s*&lda,\s*work,\s*&lwork,\s*&info\s*\)/dormqr_(\&side, \&t, \&n, \&n, \&n, X, \&lda, tau, c, \&lda, work, \&lwork, \&info, (size_t)1, (size_t)1)/s if !/size_t/' \
  "$root/src/StatLib.cpp"
