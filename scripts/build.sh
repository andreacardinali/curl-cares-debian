#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

log(){
  printf '[curl-cares-build] %s\n' "$*"
}

[[ -n "${APT_GPG_PRIVATE_KEY:-}" ]] || { log 'Missing APT_GPG_PRIVATE_KEY'; exit 1; }
[[ -n "${APT_GPG_KEY_ID:-}" ]] || { log 'Missing APT_GPG_KEY_ID'; exit 1; }

log 'Enabling Debian source repositories'

cat >/etc/apt/sources.list.d/debian-src.sources <<'EOF'
Types: deb-src
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main

Types: deb-src
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main
EOF

apt-get update

apt-get install -y --no-install-recommends \
  build-essential \
  devscripts \
  dpkg-dev \
  apt-utils \
  libc-ares-dev \
  gnupg

apt-get build-dep -y curl

mkdir -p /build /repo
chown _apt:root /build
chmod 755 /build

cd /build

log 'Downloading Debian curl source'
apt-get source curl

cd curl-*

grep -q -- '--enable-threaded-resolver' debian/rules ||
  { log 'Unable to locate threaded resolver option'; exit 1; }

sed -i 's/--enable-threaded-resolver/--enable-ares/g' debian/rules

grep -q -- '--enable-ares' debian/rules ||
  { log 'Unable to enable c-ares'; exit 1; }

log 'Building Debian packages'
dpkg-buildpackage -us -uc -b

cd /build

cp curl_*_*.deb /repo/
cp libcurl4t64_*_*.deb /repo/

log 'Creating APT package index'

cd /repo
dpkg-scanpackages . /dev/null >Packages
gzip -9k Packages

log 'Importing repository signing key'

printf '%s\n' "$APT_GPG_PRIVATE_KEY" | gpg --batch --import

gpg --batch --armor \
  --export "$APT_GPG_KEY_ID" \
  >curl-cares-debian.asc

log 'Creating repository metadata'

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin='curl-cares-debian' \
  -o APT::FTPArchive::Release::Label='curl-cares-debian' \
  -o APT::FTPArchive::Release::Suite='trixie' \
  -o APT::FTPArchive::Release::Codename='trixie' \
  -o APT::FTPArchive::Release::Architectures='amd64' \
  release . >Release

log 'Signing repository metadata'

gpg --batch --yes \
  --local-user "$APT_GPG_KEY_ID" \
  --clearsign \
  --output InRelease \
  Release

gpg --batch --yes \
  --local-user "$APT_GPG_KEY_ID" \
  --armor \
  --detach-sign \
  --output Release.gpg \
  Release

log 'Verifying curl package'

dpkg-deb -x curl_*_amd64.deb /tmp/curl-test
dpkg-deb -x libcurl4t64_*_amd64.deb /tmp/curl-test

LD_LIBRARY_PATH=/tmp/curl-test/usr/lib/x86_64-linux-gnu \
  /tmp/curl-test/usr/bin/curl -V | grep -q 'c-ares/' ||
  { log 'Built curl does not contain c-ares support'; exit 1; }

log 'Repository build completed successfully'
