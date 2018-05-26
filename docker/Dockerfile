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

# Install git and java (taken from https://github.com/dockerfile/java/blob/master/oracle-java8/Dockerfile)
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y \
    && apt-get install -y git software-properties-common \
    && (echo oracle-java8-installer shared/accepted-oracle-license-v1-1 select true | debconf-set-selections) \
    && add-apt-repository -y ppa:webupd8team/java \
    && apt-get update -y \
    && apt-get install -y oracle-java8-installer ant \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/oracle-jdk8-installer

# Clone the repo
RUN mkdir /repo && git clone -b version/2.5 https://github.com/Ensembl/ensembl-hive.git /repo/ensembl-hive

# Install all the dependencies
RUN /repo/ensembl-hive/docker/setup_os.Ubuntu-16.04.sh \
    && /repo/ensembl-hive/docker/setup_cpan.Ubuntu-16.04.sh /repo/ensembl-hive

ENV EHIVE_ROOT_DIR "/repo/ensembl-hive"
ENV PATH "/repo/ensembl-hive/scripts:$PATH"
ENV PERL5LIB "/repo/ensembl-hive/modules:$PERL5LIB"
ENV JAVA_HOME /usr/lib/jvm/java-8-oracle

ENTRYPOINT [ "/repo/ensembl-hive/scripts/dev/simple_init.py" ]
CMD [ "/bin/bash" ]
