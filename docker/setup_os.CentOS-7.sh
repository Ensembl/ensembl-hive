#!/bin/bash

set -e

# Proc::Daemon trick: we need version 0.23 but only version 0.19 is in the
# centos archives. cpanm will fail building 0.23 if 0.19 is around, so we
# need to build 0.23 before we install anything else
yum install -y perl-App-cpanminus perl-Test-Simple perl-Proc-ProcessTable
tmpdir=$(mktemp -d)
echo "requires 'Proc::Daemon', '0.23';" > "$tmpdir/cpanfile"
cpanm --installdeps --notest --with-recommends "$tmpdir"
rmdir "$tmpdir"

# install required extra software
yum install -y curl \
	       sqlite perl-DBD-SQLite postgresql perl-DBD-Pg mariadb perl-DBD-MySQL perl-DBI \
               perl-Capture-Tiny perl-DateTime perl-Time-Piece perl-HTML-Parser perl-JSON \
               perl-Test-Exception perl-Test-Simple perl-Test-Warn perl-Test-Warnings perl-Test-File-Contents perl-Test-Perl-Critic perl-GraphViz \
               gnuplot perl-BSD-Resource

