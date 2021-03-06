#!/bin/bash

set -eo pipefail
#set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TMP_DIR="/var/tmp"
UPLOADER_DIR="$HOME/package-uploads"
UPLOADER_PROCESSED_DIR="$HOME/package-uploads-processed"
REPO_STAGING_BASE="$HOME/package-repo-staging"

IMAGE_UPLOADER_DIR="$HOME/image-uploads"
IMAGE_UPLOADER_PROCESSED_DIR="$HOME/image-uploads-processed"

SNAPSHOTS_DIR="/var/www/html/snapshots"
EXPERIMENTAL_DIR="/var/www/html/experimental"

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
  if [[ ! -f "${DIR}/usign" ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find ./usign, please build it, see README"
  fi
  if [[ ! -f "$HOME/keys/secret.key" ]]; then
    MISSING_DEP=1
    echo "Missing dependency: unable to find $HOME/keys/secret.key, see README"
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
  branch=$4

  if [[ "${branch}" == "main" ]]; then
    REPO="${SNAPSHOTS_DIR}/packages/${arch}/generic"
  else
    REPO="${EXPERIMENTAL_DIR}/packages/${branch}/${arch}/generic"
  fi
  mkdir -p "${REPO}"

  PWD=`pwd`
  REPO_STAGING_DIR="${REPO_STAGING_BASE}/${branch}/${profile}/${device}"
  mkdir -p "${REPO_STAGING_DIR}"

  cp -p $device/*.ipk "${REPO_STAGING_DIR}"

  cd "${REPO_STAGING_DIR}"

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

  # Sign the Packages file with our usign key
  ${DIR}/usign -S -m Packages -s ~uploader/keys/secret.key -x Packages.sig -c "signature from MassMesh Packaging team"

  FILE_COUNT_IN_STAGING=`ls -C1 ${REPO_STAGING_DIR}|wc -l`
  FILE_COUNT_IN_REPO=`ls -C1 ${REPO}|wc -l`
  if [[ $FILE_COUNT_IN_STAGING -lt $FILE_COUNT_IN_REPO ]]; then
    echo
    echo "!!!!!! ERROR: staging (${REPO_STAGING_DIR}) contains fewer files ($FILE_COUNT_IN_STAGING) than the repository (${REPO}) ($FILE_COUNT_IN_REPO)"
    echo "Not updating repository, and switching to dry run mode."
    echo
    NOOP="--noop"
    EXTRA="--dry-run "
  fi
  rsync -aAHXv --delete $EXTRA"${REPO_STAGING_DIR}/" "${REPO}/"
  cd "${PWD}"
}

update_images() {
  dir=$1
  profile=$2
  device=$3
  branch=$4

  if [[ "${branch}" == "main" ]]; then
    DEST="${SNAPSHOTS_DIR}/images/${profile}/${device}"
  else
    DEST="${EXPERIMENTAL_DIR}/images/${branch}/${profile}/${device}"
  fi
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
  #   `mktemp -d -p $HOME/uploads ci.XXXXXXXX`
  cd "${UPLOADER_DIR}"
  # Iterate over directories in $UPLOADER_DIR, sorted by oldest first
  for i in `ls -cd -tr ci.* 2>/dev/null || true`; do
    # Must be a directory
    if [ ! -d "${i}" ]; then
      continue
    fi
    cd "${i}"
    echo "Processing ${UPLOADER_DIR}/${i}"
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
      # determine branch
      branch=`ls ${device}.branch.* 2>/dev/null || true`
      branch=${branch##${device}.branch.}
      if [[ -z "${branch}" ]]; then
        echo "branch file for ${device} not found, skipping ${i}"
        continue
      fi
      update_packages "${device}" "${profile}" "${arch}" "${branch}"
      if [[ -z "$NOOP" ]]; then
        cd ${UPLOADER_DIR}
        mkdir -p ${UPLOADER_PROCESSED_DIR}
        mv "${i}" "${UPLOADER_PROCESSED_DIR}/"
      fi
      echo "Processing ${UPLOADER_DIR}/${i} complete"
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
      # determine branch
      branch=`ls ${device}.branch.* 2>/dev/null || true`
      branch=${branch##${device}.branch.}
      if [[ -z "${branch}" ]]; then
        echo "branch file for ${device} not found, skipping ${i}"
        continue
      fi
      update_images "${IMAGE_UPLOADER_DIR}/${i}" "${profile}" "${device}" "${branch}"
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
