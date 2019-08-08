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
# docker build -t ensembl-hive -f docker/Dockerfile $EHIVE_ROOT_DIR
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

# 1. Get the current ensembl-hive repo and remove stuff we don't want
FROM alpine:3.9.4 AS repo
RUN apk add git
ADD . /tmp/ensembl-hive
# git clean will remove things listed in .gitignore, incl. .pyc, .jar etc
# but will leave local modifications and other files, thus allowing local tests
RUN cd /tmp/ensembl-hive && git clean -d -X -f
RUN rm -rf /tmp/ensembl-hive/.git

# Build the Java wrapper
FROM maven:3.6-jdk-12-alpine AS java_builder
COPY --from=repo /tmp/ensembl-hive/wrappers/java /tmp/java_wrapper
RUN cd /tmp/java_wrapper && mvn package

# Dependencies
FROM ubuntu:16.04 AS os_installer
ADD docker/setup_os.Ubuntu-16.04.sh /tmp/
RUN /tmp/setup_os.Ubuntu-16.04.sh

# In case not all the dependencies have been listed in setup_os.Ubuntu-16.04.sh
FROM os_installer AS cpan_builder
RUN apt-get update -y
RUN apt-get install -y cpanminus build-essential
ADD cpanfile /tmp/
RUN cpanm --installdeps --with-recommends /tmp/

# Bundle everything together
FROM os_installer
COPY --from=repo /tmp/ensembl-hive /repo/ensembl-hive
COPY --from=cpan_builder /usr/local /usr/local
COPY --from=java_builder /tmp/java_wrapper/target/eHive-*-jar-with-dependencies.jar /repo/ensembl-hive/wrappers/java/target/
ENV EHIVE_ROOT_DIR "/repo/ensembl-hive"
ENV PATH "/repo/ensembl-hive/scripts:$PATH"
ENV PERL5LIB "/repo/ensembl-hive/modules:$PERL5LIB"

ENTRYPOINT [ "/repo/ensembl-hive/scripts/dev/simple_init.py" ]
CMD [ "/bin/bash" ]
