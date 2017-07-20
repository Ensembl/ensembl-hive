#!/bin/bash

# $PWD is the user manual, which I want to keep clean
cd "$HOME"

# Exit if we have already installed the dependencies
[ -d packages ] && exit 0;

# List of extra packages we need
echo http://archive.ubuntu.com/ubuntu/pool/main/libd/libdbi-perl/libdbi-perl_1.634-1build1_amd64.deb \
     http://archive.ubuntu.com/ubuntu/pool/universe/libd/libdbd-sqlite3-perl/libdbd-sqlite3-perl_1.50-1_amd64.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libj/libjson-xs-perl/libjson-xs-perl_3.010-2build1_amd64.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libj/libjson-perl/libjson-perl_2.90-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libc/libcommon-sense-perl/libcommon-sense-perl_3.74-1build1_amd64.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libt/libtypes-serialiser-perl/libtypes-serialiser-perl_1.0-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/universe/libx/libxml-xpath-perl/libxml-xpath-perl_1.30-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/universe/libp/libparse-recdescent-perl/libparse-recdescent-perl_1.967013+dfsg-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libi/libipc-run-perl/libipc-run-perl_0.94-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/main/libi/libio-pty-perl/libio-pty-perl_1.08-1.1build1_amd64.deb \
     http://archive.ubuntu.com/ubuntu/pool/universe/libg/libgraphviz-perl/libgraphviz-perl_2.20-1_all.deb \
     http://archive.ubuntu.com/ubuntu/pool/universe/d/doxypy/doxypy_0.4.2-1.1_all.deb \
| xargs -n 1 curl -O

mkdir packages
for i in *.deb; do dpkg -x "$i" packages/; done

git clone --branch master --depth 1 https://github.com/Ensembl/ensembl.git

