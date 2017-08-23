# This is a Dockerfile to run eHive scripts (init_pipeline.pl, beekeeper.pl, runWorker.pl) in a container
#
## Build the image
# docker build -t ensembl-hive .
#
## Check that the test-suite works (guest_language.t is expected to fail
# docker run -e EHIVE_TEST_PIPELINE_URLS=sqlite:/// ensembl-hive prove -r /repo/ensembl-hive/t
#
## Open a session in a new container (will run bash)
# docker run -it ensembl-hive
#
## Initialize and run a pipeline
# docker run -it ensembl-hive init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $URL
# docker run -it ensembl-hive beekeeper.pl -url $URL -loop -sleep 0.2
# docker run -it ensembl-hive runWorker.pl -url $URL


FROM ubuntu:16.04

RUN apt-get update -y \
                       # Needed to clone the checkout, to use cpanm and forbasic help
 && apt-get install -y curl git perl-doc \
		       # Database-related dependencies
                       sqlite3 libdbd-sqlite3-perl postgresql-client libdbd-pg-perl mysql-client libdbd-mysql-perl libdbi-perl \
		       # Required Perl modules
		       libcapture-tiny-perl libdatetime-perl libhtml-parser-perl libjson-perl \
		       # Perl modules needed for the test-suite
		       libtest-exception-perl libtest-simple-perl libtest-warn-perl libtest-warnings-perl libtest-file-contents-perl libtest-perl-critic-perl libgraphviz-perl \
		       # Recommendations
		       libgetopt-argvfile-perl libchart-gnuplot-perl libbsd-resource-perl \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

## Useful for debugging
# RUN apt-get install netcat.openbsd vim perl-doc iputils-ping net-tools apt-file -y

RUN ln -s /usr/bin/mariadb_config /usr/bin/mysql_config

RUN mkdir /repo && git clone -b master https://github.com/Ensembl/ensembl-hive.git /repo/ensembl-hive

# Install the missing dependencies (if any)
# NOTE: buildDeps may have to be extended to include some lib*-dev packages
#       such as libmariadb-client-lgpl-dev libpq-dev libsqlite3-dev libexpat1-dev
# The cpanm command is wrapped with apt-get install / purge to keep the
# image small
RUN buildDeps=' \
      cpanminus \
      build-essential \
    ' \
    && apt-get update -y \
    && apt-get install -y $buildDeps \
    && rm -rf /var/lib/apt/lists/* \
    && cpanm --installdeps --with-recommends /repo/ensembl-hive \
    && apt-get purge -y --auto-remove $buildDeps

ENV PATH "/repo/ensembl-hive/scripts:$PATH"
ENV PERL5LIB "/repo/ensembl-hive/modules:$PERL5LIB"

CMD [ "/bin/bash" ]
