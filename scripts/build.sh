#!/bin/bash

set -o pipefail

SCRIPT_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
source ${SCRIPT_DIR}/functions.sh

# INCLUDE_REPOS is a list of all GitHub repositories to scan for deb, rpm, and apk packages.
INCLUDE_REPOS=${INCLUDE_REPOS:-containerssh/agent}
# Domain is the root domain of the packages repository.
ROOT_URL=${ROOT_URL:-https://packages.containerssh.io}
# GPG_EMAIL is the e-mail address used for GPG signing.
GPG_EMAIL=${GPG_EMAIL:-handshake@containerssh.io}
# Branch is the branch to check out.
BRANCH=${BRANCH:-gh-pages}
# DIR is the directory to check out the gh-pages branch to.
DIR=${DIR:-$($REALPATH_BIN ${SCRIPT_DIR}/../gh-pages)}
# SRCDIR is the directory to copy the base files from.
SRCDIR=${SRCDIR:-$($REALPATH_BIN ${SCRIPT_DIR}/../src)}
# DEBIAN_PATH sets the path for the debian repository
DEBIAN_PATH=/debian
# Only push if we are on this branch
PUSH_BRANCH=${PUSH_BRANCH:-main}
# Current branch to use for determining if push is needed
REPO_BRANCH=${REPO_BRANCH:-$(cd $SRCDIR && $GIT_BIN symbolic-ref HEAD | $SED_BIN -e 's#refs/heads/##')}
# REPO is the repository URL
REPO=${REPO:-$($GIT_BIN remote -v | $HEAD_BIN -n 1 | $AWK_BIN ' { print $2 } ')}
if [ ! -n $REPO ]; then
  echo "Could not determine remote for GitHub pages. Please provide the REPO parameter with a remote to push to."
  exit 1
fi

clone
if [ $? -ne 0 ]; then
  echo "Failed to clone repository." >&2
  exit 5
fi

syncfiles $SRCDIR $DIR
if [ $? -ne 0 ]; then
  echo "Failed to sync base files to repository." >&2
  exit 6
fi

debianrepo ${DIR}${DEBIAN_PATH} $INCLUDE_REPOS $GPG_EMAIL $GITHUB_TOKEN
if [ $? -ne 0 ]; then
  echo "Failed to build debian repository." >&2
  exit 7
fi

if [ "${REPO_BRANCH}" = "${PUSH_BRANCH}" ]; then
  push ${DIR} ${BRANCH}
  if [ $? -ne 0 ]; then
    echo "Push failed" >&2
    exit 8
  fi
else
  echo "Current branch (${REPO_BRANCH}) doesn't match push branch (${PUSH_BRANCH}), skipping deployment."
fi