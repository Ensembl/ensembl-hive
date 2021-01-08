#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

# Proc::Daemon trick: we need version 0.23 but only version 0.19 is in the
# centos archives. cpanm will fail building 0.23 if 0.19 is around, so we
# need to build 0.23 before we install anything else
yum install -y perl-App-cpanminus perl-Test-Simple perl-Proc-ProcessTable
tmpdir=$(mktemp -d)
echo "requires 'Proc::Daemon', '0.23';" > "$tmpdir/cpanfile"
cpanm --installdeps --notest --with-recommends "$tmpdir"
rm -r "$tmpdir"

# install required extra software
yum install -y curl \
	       sqlite perl-DBD-SQLite postgresql perl-DBD-Pg mariadb perl-DBD-MySQL perl-DBI \
               perl-Capture-Tiny perl-DateTime perl-Time-Piece perl-HTML-Parser perl-JSON perl-Email-Sender \
               perl-Test-Exception perl-Test-Simple perl-Test-Warn perl-Test-Warnings perl-Test-File-Contents perl-Test-Perl-Critic perl-Test-Fatal perl-GraphViz \
               gnuplot perl-BSD-Resource

