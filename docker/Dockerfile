# This is a Dockerfile to run eHive scripts (init_pipeline.pl, beekeeper.pl, runWorker.pl) in a container
#
# docker build -t ensembl-hive .
#
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive		# assume bash 
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url $URL
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive beekeeper.pl -url $URL -loop -sleep 0.2
# docker run -it -e PATH=/repo/ensembl-hive/scripts:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin ensembl-hive runWorker.pl -url $URL


FROM ubuntu:16.04

RUN mkdir /repo

RUN apt-get update -y \
 && apt-get install git build-essential curl sqlite3 mysql-client libmariadb-client-lgpl-dev libpq-dev libexpat1-dev graphviz -y \
 && apt-get install netcat.openbsd vim perl-doc -y \
 && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# RUN apt-get install iputils-ping net-tools apt-file -y

RUN ln -s /usr/bin/mariadb_config /usr/bin/mysql_config

RUN curl -L https://cpanmin.us | perl - App::cpanminus

RUN cd /repo ; git clone https://github.com/Ensembl/ensembl-hive.git

RUN cd /repo/ensembl-hive ; git checkout master

RUN cpanm --installdeps --with-recommends /repo/ensembl-hive

	# for the processes you run in an interactive bash
RUN echo "export PATH=$PATH:/repo/ensembl-hive/scripts" >>/root/.bashrc

CMD [ "/bin/bash" ]
