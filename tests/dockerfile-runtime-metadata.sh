#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
DOCKERFILE="$ROOT_DIR/Dockerfile"

awk '
  /^# ---- runtime ----/ { runtime=1 }
  runtime && /^ARG USQUE_REF=main$/ { has_usque_ref=1 }
  runtime && /^ARG BUILD_VARIANT=lite$/ { has_build_variant=1 }
  runtime && /USQUE_VERSION="\$\{USQUE_REF\}"/ { has_version_env=1 }
  runtime && /USQUE_IMAGE_VARIANT="\$\{BUILD_VARIANT\}"/ { has_variant_env=1 }
  END {
    if (!has_usque_ref) {
      print "missing runtime ARG USQUE_REF=main" > "/dev/stderr"
      exit 1
    }
    if (!has_build_variant) {
      print "missing runtime ARG BUILD_VARIANT=lite" > "/dev/stderr"
      exit 1
    }
    if (!has_version_env) {
      print "missing USQUE_VERSION env" > "/dev/stderr"
      exit 1
    }
    if (!has_variant_env) {
      print "missing USQUE_IMAGE_VARIANT env" > "/dev/stderr"
      exit 1
    }
  }
' "$DOCKERFILE"
