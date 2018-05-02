#!/bin/bash

set -e

apt-get update
apt-get install -y curl perl-doc \
                   sqlite3 libdbd-sqlite3-perl postgresql-client libdbd-pg-perl mysql-client libdbd-mysql-perl libdbi-perl \
                   libcapture-tiny-perl libdatetime-perl libhtml-parser-perl libjson-perl libemail-mime-perl libemail-sender-perl libemail-simple-perl libproc-daemon-perl \
                   libtest-exception-perl libtest-simple-perl libtest-warn-perl libtest-warnings-perl libtest-file-contents-perl libtest-perl-critic-perl libtest-fatal-perl libgraphviz-perl \
                   libgetopt-argvfile-perl libchart-gnuplot-perl libbsd-resource-perl

## Useful for debugging
#apt-get install -y netcat.openbsd vim perl-doc iputils-ping net-tools apt-file

# Cleanup the cache to reduce the disk footprint
apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Needed for Perl DBI
ln -s /usr/bin/mariadb_config /usr/bin/mysql_config

