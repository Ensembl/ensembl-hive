#!/bin/bash

set -e

# NOTE: buildDeps may have to be extended to include some lib*-dev packages
#       such as libmariadb-client-lgpl-dev libpq-dev libsqlite3-dev libexpat1-dev
buildDeps='
  cpanminus
  build-essential
'
apt-get update -y
apt-get install -y $buildDeps

for arg
do
	cpanm --installdeps --with-recommends "$arg"
done
# Cleanup the cache and remove the build dependencies to reduce the disk footprint
rm -rf /var/lib/apt/lists/*
apt-get purge -y --auto-remove $buildDeps

