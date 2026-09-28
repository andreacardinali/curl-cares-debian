#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

log(){
  printf '[curl-cares-build] %s\n' "$*"
}

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
  libc-ares-dev

apt-get build-dep -y curl

mkdir -p /build /repo
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
cd /
dpkg-scanpackages repo /dev/null >repo/Packages
gzip -9k repo/Packages

log 'Build completed'
