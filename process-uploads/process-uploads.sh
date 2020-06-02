#!/bin/bash

set -eo pipefail
#set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TMP_DIR="/var/tmp"
UPLOADER_DIR="/home/uploader/uploads"
UPLOADER_PROCESSED_DIR="/home/uploader/uploads-processed"
REPO_STAGING_DIR="/home/uploader/repo-staging"
REPO_DIR="/var/www/html/snapshots/packages"

IMAGE_UPLOADER_DIR="/home/uploader/image-uploads"
IMAGE_UPLOADER_PROCESSED_DIR="/home/uploader/image-uploads-processed"
IMAGE_DIR="/var/www/html/snapshots/images"

USER=uploader

dependencies() {
  set +e
  MISSING_DEP=0
  which rsync >/dev/null
  if [[ $? -ne 0 ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find rsync, please install, e.g.: apt-get install rsync"
  fi
  which stat >/dev/null
  if [[ $? -ne 0 ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find stat, please install, e.g.: apt-get install coreutils"
  fi
  if [[ ! -f "${DIR}/mkhash" ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find ./mkhash, please build it from mkhash.c"
  fi
  if [[ ! -f "${DIR}/ipkg-make-index.sh" ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find ./ipkg-make-index.sh"
  fi
  if [[ $MISSING_DEP -ne 0 ]]; then
    exit 1
  fi
  set -e
}

update_packages() {
  device=$1
  profile=$2
  arch=$3

  REPO="${REPO_DIR}/${arch}/generic"
  mkdir -p "${REPO}"

  PWD=`pwd`
  cd "${REPO_STAGING_DIR}/${profile}/${device}"

  # what follows is borrowed from package/Makefile in the openwrt SDK
  # the mkhash binary needs to be built and in the path. The c source is in this
  # directory.
  $DIR/ipkg-make-index.sh . 2>&1 > Packages.manifest
  grep -vE '^(Maintainer|LicenseFiles|Source|SourceName|Require)' Packages.manifest > Packages
  case "$$(((64 + $$(stat -L -c%s Packages)) % 128))" in
  110|111) \
    { echo ""; echo ""; } >> Packages
    ;;
  esac
  gzip -9nc Packages > Packages.gz
  EXTRA=""
  if [[ -n "$NOOP" ]]; then
    EXTRA="--dry-run "
  fi
  FILE_COUNT_IN_STAGING=`ls -C1 ${REPO_STAGING_DIR}/${profile}/${device}|wc -l`
  FILE_COUNT_IN_REPO=`ls -C1 ${REPO}|wc -l`
  if [[ $FILE_COUNT_IN_STAGING < $FILE_COUNT_IN_REPO ]]; then
    echo
    echo "!!!!!! ERROR: staging (${REPO_STAGING_DIR}/${profile}/${device}) contains fewer files than the repository (${REPO})"
    echo "Not updating repository, and switching to dry run mode"
    echo
    NOOP="--noop"
    EXTRA="--dry-run "
  fi
  rsync -aAHXv --delete $EXTRA"${REPO_STAGING_DIR}/${profile}/${device}/" "${REPO}/"
  cd "${PWD}"
}

update_images() {
  dir=$1
  profile=$2
  device=$3

  DEST="${IMAGE_DIR}/${profile}/${device}"
  mkdir -p "${DEST}"

  EXTRA=""
  if [[ -n "$NOOP" ]]; then
    EXTRA="--dry-run "
  fi
  FILE_COUNT_IN_UPLOAD=`ls -C1 ${dir}/${device}|wc -l`
  FILE_COUNT_IN_DEST=`ls -C1 ${DEST}|wc -l`
  if [[ $FILE_COUNT_IN_UPLOAD < $FILE_COUNT_IN_DEST ]]; then
    echo
    echo "!!!!!! ERROR: upload (${dir}/${device}) contains fewer files than the destination (${DEST})"
    echo "Not updating destination, switching to dry run mode"
    echo
    NOOP="--noop"
    EXTRA="--dry-run "
  fi
  rsync -aAHXv --delete $EXTRA"${dir}/${device}/" "${DEST}/"
}

process_package_uploads() {
  # The sub directories in $UPLOADER_DIR are created with
  #   `mktemp -d -p /home/uploader/uploads ci.XXXXXXXX`
  cd "${UPLOADER_DIR}"
  # Iterate over directories in $UPLOADER_DIR, sorted by oldest first
  for i in `ls -cd -tr ci.* 2>/dev/null || true`; do
    # Must be a directory
    if [ ! -d "${i}" ]; then
      continue
    fi
    cd "${i}"
    for j in `ls *.uploaded 2>/dev/null || true`; do
      device=${j%%.uploaded}
      if [ ! -d "${device}" ]; then
        echo "directory not found for ${device}, skipping ${i}"
        continue
      fi
      # determine profile
      profile=`ls ${device}.profile.* 2>/dev/null || true`
      profile=${profile##${device}.profile.}
      if [[ -z "${profile}" ]]; then
        echo "profile file for ${device} not found, skipping ${i}"
        continue
      fi
      # determine arch
      arch=`ls ${device}.arch.* 2>/dev/null || true`
      arch=${arch##${device}.arch.}
      if [[ -z "${arch}" ]]; then
        echo "arch file for ${device} not found, skipping ${i}"
        continue
      fi
      mkdir -p "${REPO_STAGING_DIR}/${profile}/${device}"
      cp -p $device/*.ipk "${REPO_STAGING_DIR}/${profile}/${device}"
      update_packages "${device}" "${profile}" "${arch}"
      if [[ -z "$NOOP" ]]; then
        cd ${UPLOADER_DIR}
        mkdir -p ${UPLOADER_PROCESSED_DIR}
        mv "${i}" "${UPLOADER_PROCESSED_DIR}/"
      fi
    done
    cd "${UPLOADER_DIR}"
  done
}

process_image_uploads() {
  cd "${IMAGE_UPLOADER_DIR}"
  # Iterate over directories in $IMAGE_UPLOADER_DIR, sorted by oldest first
  for i in `ls -cd -tr ci.* 2>/dev/null || true`; do
    # Must be a directory
    if [ ! -d "${i}" ]; then
      continue
    fi
    cd "${i}"
    for j in `ls *.uploaded 2>/dev/null || true`; do
      device=${j%%.uploaded}
      if [ ! -d "${device}" ]; then
        echo "directory not found for ${device}, skipping ${i}"
        continue
      fi
      # determine profile
      profile=`ls ${device}.profile.* 2>/dev/null || true`
      profile=${profile##${device}.profile.}
      if [[ -z "${profile}" ]]; then
        echo "profile file for ${device} not found, skipping ${i}"
        continue
      fi
      update_images "${IMAGE_UPLOADER_DIR}/${i}" "${profile}" "${device}"
      if [[ -z "$NOOP" ]]; then
        cd ${IMAGE_UPLOADER_DIR}
        mkdir -p ${IMAGE_UPLOADER_PROCESSED_DIR}
        mv "${i}" "${IMAGE_UPLOADER_PROCESSED_DIR}/"
      fi
    done
    cd "${IMAGE_UPLOADER_DIR}"
  done
}

main() {
  dependencies

  NOOP=$1
  if [[ -n "$NOOP" ]]; then
    echo
    echo "**** RUNNING IN DRY RUN/NOOP MODE ****"
    echo
  fi

  process_package_uploads
  process_image_uploads

}

main $@
