# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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
    && apt-get install -y git software-properties-common openjdk-8-jdk ant \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Clone the repo
RUN mkdir /repo && git clone -b version/2.5 https://github.com/Ensembl/ensembl-hive.git /repo/ensembl-hive

# Install all the dependencies
RUN /repo/ensembl-hive/docker/setup_os.Ubuntu-16.04.sh \
    && /repo/ensembl-hive/docker/setup_cpan.Ubuntu-16.04.sh /repo/ensembl-hive

ENV EHIVE_ROOT_DIR "/repo/ensembl-hive"
ENV PATH "/repo/ensembl-hive/scripts:$PATH"
ENV PERL5LIB "/repo/ensembl-hive/modules:$PERL5LIB"

ENTRYPOINT [ "/repo/ensembl-hive/scripts/dev/simple_init.py" ]
CMD [ "/bin/bash" ]
