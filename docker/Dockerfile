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

# Install git
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y && apt-get install -y git && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Clone the repo
RUN mkdir /repo && git clone -b master https://github.com/Ensembl/ensembl-hive.git /repo/ensembl-hive

# Install all the dependencies
RUN /repo/ensembl-hive/docker/setup_os.Ubuntu-16.04.sh
# Install the missing dependencies (if any)
RUN /repo/ensembl-hive/docker/setup_cpan.Ubuntu-16.04.sh /repo/ensembl-hive

ENV PATH "/repo/ensembl-hive/scripts:$PATH"
ENV PERL5LIB "/repo/ensembl-hive/modules:$PERL5LIB"

CMD [ "/bin/bash" ]
