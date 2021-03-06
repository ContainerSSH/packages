#!/bin/bash

function check_binary() {
  NAME=$1
  ENV=$2
  BIN=$3
  if [ ! -x $BIN ]; then
    echo "No $NAME binary found at ${BIN}. Please provide the $ENV environment variable pointing to the $NAME binary." >&2
    exit 1
  fi
}

export GPG_BIN=${GPG_BIN:-/usr/bin/gpg}
check_binary gpg GPG_BIN $GPG_BIN

export GPGAGENT_BIN=${GPGAGENT_BIN:-/usr/bin/gpg-agent}
check_binary gpg-agent GPGAGENT_BIN $GPGAGENT_BIN

export GREP_BIN=${GREP_BIN:-/bin/grep}
check_binary grep GREP_BIN $GREP_BIN

export GZIP_BIN=${GZIP_BIN:-/bin/gzip}
check_binary gzip GZIP_BIN $GZIP_BIN

export APT_FTPARCHIVE_BIN=${APT_FTPARCHIVE_BIN:-/usr/bin/apt-ftparchive}
check_binary apt-ftparchive APT_FTPARCHIVE_BIN $APT_FTPARCHIVE_BIN

export DPKG_SCANPACKAGES_BIN=${DPKG_SCANPACKAGES_BIN:-/usr/bin/dpkg-scanpackages}
check_binary dpkg-scanpackages DPKG_SCANPACKAGES_BIN $DPKG_SCANPACKAGES_BIN

export GIT_BIN=${GIT_BIN:-/usr/bin/git}
check_binary git GIT_BIN $GIT_BIN

export HEAD_BIN=${HEAD_BIN:-/usr/bin/head}
check_binary head HEAD_BIN $HEAD_BIN

export AWK_BIN=${AWK_BIN:-/usr/bin/awk}
check_binary awk AWK_BIN $AWK_BIN

export RSYNC_BIN=${RSYNC_BIN:-/usr/bin/rsync}
check_binary rsync RSYNC_BIN $RSYNC_BIN

export REALPATH_BIN=${REALPATH_BIN:-/usr/bin/realpath}
check_binary realpath REALPATH_BIN $REALPATH_BIN

export JQ_BIN=${JQ_BIN:-/usr/bin/jq}
check_binary jq JQ_BIN $JQ_BIN

export CURL_BIN=${CURL_BIN:-/usr/bin/curl}
check_binary curl CURL_BIN $CURL_BIN

export MKDIR_BIN=${MKDIR_BIN:-/bin/mkdir}
check_binary mkdir MKDIR_BIN $MKDIR_BIN

export RM_BIN=${RM_BIN:-/bin/rm}
check_binary rm RM_BIN $RM_BIN

export SED_BIN=${SED_BIN:-/bin/sed}
check_binary sed SED_BIN $SED_BIN

export BASENAME_BIN=${BASENAME_BIN:-/usr/bin/basename}
check_binary basename BASENAME_BIN $BASENAME_BIN

export BASE64_BIN=${BASE64_BIN:-/usr/bin/base64}
check_binary base64 BASE64_BIN $BASE64_BIN

function clone() {
  CLONEREPO=$1
  TARGETDIR=$2
  echo "Cloning or updating git repository at $TARGETDIR..."
  if [ ! -d $TARGETDIR ]; then
    $GIT_BIN clone $CLONEREPO $TARGETDIR
    if [ $? -ne 0 ]; then
      echo "Failed to clone to '$TARGETDIR'." >&2
      return 2
    fi
  elif [ ! -d $TARGETDIR/.git ]; then
    echo "Could not find .git directory in existing $TARGETDIR directory." >&2
    return 2
  fi
  cd $TARGETDIR
  if [ $? -ne 0 ]; then
    echo "Failed switch to '$TARGETDIR' directory." >&2
    return 2
  fi
  $GIT_BIN reset --hard >/dev/null
  if [ $? -ne 0 ]; then
    echo "Failed to reset git repository at '$TARGETDIR'." >&2
    return 2
  fi
  $GIT_BIN clean -fd >/dev/null
  if [ $? -ne 0 ]; then
    echo "Failed to clean git repository at '$TARGETDIR'." >&2
    return 2
  fi
  CURRENT_BRANCH=$($GIT_BIN branch 2>/dev/null)
  if [ "${CURRENT_BRANCH}" != "* ${BRANCH}" ]; then
    $GIT_BIN checkout $BRANCH >/dev/null
    if [ $? -ne 0 ]; then
      echo "Failed to switch to '$BRANCH' branch." >&2
      return 2
    fi
  fi
  return 0
}

function syncfiles() {
  SRCDIR=$1
  DSTDIR=$2

  if [ ! -d $SRCDIR ]; then
    echo "Source directory does not exist: $SRCDIR" >&2
    return 3
  fi
  if [ ! -d $DSTDIR ]; then
    echo "Destination directory does not exist: $DSTDIR" >&2
    return 3
  fi

  echo "Copying files from $SRCDIR to $DSTDIR..."
  $RSYNC_BIN -az $SRCDIR/ $DSTDIR/
  return $?
}

function github() {
  URI=$1
  GITHUB_TOKEN=$2
  if [ -n "$GITHUB_TOKEN" ]; then
    $CURL_BIN --fail-early -f -q \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com$URI
    return $?
  else
    $CURL_BIN --fail-early -f -q \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com$URI
    return $?
  fi
}

function github_download() {
  URL=$1
  GITHUB_TOKEN=$2
  if [ -n "$GITHUB_TOKEN" ]; then
    $CURL_BIN --fail-early -f -L -q \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      $URL
  else
    $CURL_BIN --fail-early -f -L -q \
      $URL
  fi
  return $?
}

function get_release_assets() {
  RELEASE_REPO=$1
  RELEASE_ID=$2
  GITHUB_TOKEN=$3
  github /repos/$RELEASE_REPO/releases/$RELEASE_ID/assets $GITHUB_TOKEN | $JQ_BIN '.[].browser_download_url | @text' | $SED_BIN -e 's/"/ /g'
  if [ $? -ne 0 ]; then
    echo "Failed to fetch assets for $RELEASE_REPO release $RELEASE_ID." >&2
    return 1
  fi
}

function get_repo_assets() {
  RELEASE_REPO=$1
  GITHUB_TOKEN=$2
  RELEASES=$(github /repos/$RELEASE_REPO/releases $GITHUB_TOKEN | $JQ_BIN '.[].id | @text' | $SED_BIN -e 's/"/ /g')
  if [ $? -ne 0 ]; then
    echo "Failed to list releases." >&2
    return 1
  fi
  for RELEASE_ID in $RELEASES; do
    get_release_assets $RELEASE_REPO $RELEASE_ID $GITHUB_TOKEN
    if [ $? -ne 0 ]; then
      return 1
    fi
  done
}

function get_all_assets() {
  REPOS=$1
  GITHUB_TOKEN=$2
  for R in $REPOS; do
    get_repo_assets $R $GITHUB_TOKEN
    if [ $? -ne 0 ]; then
      return $?
    fi
  done
}

function debianrepo() {
  DIR=$1
  SOURCE_REPOS=$2
  GPG_EMAIL=$3
  GITHUB_TOKEN=$4
  echo "Downloading Debian packages..."

  $MKDIR_BIN -p $DIR
  if [ $? -ne 0 ]; then
    echo "Failed to ensure Debian directory '$DIR' exists." >&2
    return 4
  fi
  cd $DIR
  if [ $? -ne 0 ]; then
    echo "Failed to change to debian directory '$DIR'." >&2
    return 1
  fi

  ASSETS=$(get_all_assets $SOURCE_REPOS $GITHUB_TOKEN)
  if [ $? -ne 0 ]; then
    return $?
  fi
  for ASSET in $ASSETS; do
    if [[ "$ASSET" == *.deb ]]; then
      FILENAME=$($BASENAME_BIN $ASSET)
      if [ ! -f "${DIR}/${FILENAME}" ]; then
        github_download $ASSET $GITHUB_TOKEN >${DIR}/${FILENAME}
        if [ $? -ne 0 ]; then
          echo "Failed to download asset '$ASSET'." >&2
          return 1
        fi
      fi
    fi
  done
  cd $DIR
  $DPKG_SCANPACKAGES_BIN --multiversion . >$DIR/Packages
  if [ $? -ne 0 ]; then
    echo "dpkg-scanpackages failed." >&2
    return 1
  fi
  $GZIP_BIN -k -f $DIR/Packages >/dev/null
  if [ $? -ne 0 ]; then
    echo "gzipping Packages failed." >&2
    return 1
  fi
  $APT_FTPARCHIVE_BIN -q release $DIR > $DIR/Release
  if [ $? -ne 0 ]; then
    echo "apt-ftparchive failed." >&2
    return 1
  fi
  $GPG_BIN --batch --default-key "${GPG_EMAIL}" -abs -o - $DIR/Release > $DIR/Release.gpg
  if [ $? -ne 0 ]; then
    echo "Release.gpg failed" >&2
    return 1
  fi
  $GPG_BIN --batch --default-key "${GPG_EMAIL}" --clearsign -o - $DIR/Release > $DIR/InRelease
  if [ $? -ne 0 ]; then
    echo "InRelease failed" >&2
    return 1
  fi
  $GPG_BIN --armor --export "${GPG_EMAIL}" > $DIR/gpg
    if [ $? -ne 0 ]; then
    echo "GPG export failed" >&2
    return 1
  fi
}

function push() {
  echo "Pushing website..."
  DIR=$1
  BRANCH=$2
  $GIT_BIN config --global user.name ContainerSSH && \
    $GIT_BIN config --global user.email $GPG_EMAIL && \
    $GIT_BIN config --global commit.gpgsign true
    $GIT_BIN config --global user.signingkey $GPG_EMAIL
  if [ $? -ne 0 ]; then
    return 1
  fi
  cd $DIR
  if [ $? -ne 0 ]; then
    return 1
  fi
  $GIT_BIN add . && \
    $GIT_BIN commit -m "Package update" && \
    $GIT_BIN push -u origin $BRANCH
  if [ $? -ne 0 ]; then
    return 1
  fi
}
