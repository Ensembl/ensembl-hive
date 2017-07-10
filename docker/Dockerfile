# This is a Dockerfile to run eHive scripts (init_pipeline.pl, beekeeper.pl, runWorker.pl) in a container
#
# docker build -t ensembl-hive .
#
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive		# assume bash 
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $URL
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive beekeeper.pl -url $URL -loop -sleep 0.2
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive runWorker.pl -url $URL


FROM ubuntu:16.04

RUN apt-get update -y \
                       # Needed to clone the checkout and use cpanm
 && apt-get install -y cpanminus git build-essential \
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
RUN cpanm --installdeps --with-recommends /repo/ensembl-hive

	# for the processes you run in an interactive bash
RUN echo "export PATH=$PATH:/repo/ensembl-hive/scripts" >>/root/.bashrc

CMD [ "/bin/bash" ]
