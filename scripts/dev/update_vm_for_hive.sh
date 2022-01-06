#!/bin/sh
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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


# Commands to run on an Ensembl VM to add eHive-specific stuff
# Known to work on the Ensembl release 90 VM
#
# Just run this as a script in a terminal inside the EnsemblVM.
# chmod u+x ./update_vm_for_hive.sh
# ./update_vm_for_hive.sh

	# The following bit unfortunately has to be interactive,
	#  since the default answers are both Yes and No: 
sudo apt-get install -y sudo
# [press enter here!]

# The rest should be automatic!

	# make sure we have the environment right in the .bashrc :
echo >> ~/.bashrc
echo '# Adding eHive-specific configuration here' >> ~/.bashrc
echo >> ~/.bashrc
echo 'export ENSEMBL_REPO_ROOT_DIR=$HOME/ensembl-api-folder' >> ~/.bashrc
echo 'export PATH=$PATH:$ENSEMBL_REPO_ROOT_DIR/ensembl-hive/scripts' >> ~/.bashrc

	# make sure we have the environment right for the current session:
export ENSEMBL_REPO_ROOT_DIR=$HOME/ensembl-api-folder
export PATH=$PATH:$ENSEMBL_REPO_ROOT_DIR/ensembl-hive/scripts

	# add the SQLite and MySQL GUI:
sudo apt-get -y install sqliteman
sudo apt-get -y install mysql-workbench

	# update eHive code and check out a stable branch:
cd $ENSEMBL_REPO_ROOT_DIR/ensembl-hive
git fetch
git checkout version/2.4
git pull
export PATH=$PATH:$ENSEMBL_REPO_ROOT_DIR/ensembl-hive/scripts

	# download guiHIve:
cd $ENSEMBL_REPO_ROOT_DIR
git clone https://github.com/Ensembl/guiHive.git

	# deploy guiHive's versions:
cd $ENSEMBL_REPO_ROOT_DIR/guiHive
./guihive-deploy.sh

	# install the Go compiler:
sudo apt-get install golang
# or sudo apt-get -y install gccgo-go

	# use the Go compiler to build the guiHive server:
cd $ENSEMBL_REPO_ROOT_DIR/guiHive/server
go build

	# spawning the guiHive server:
nohup $ENSEMBL_REPO_ROOT_DIR/guiHive/server/server &

	# make sure we have GraphViz installed via cpanm (so it links with the right Perl) :
sudo apt-get -y install libgraphviz-perl
sudo apt-get -y install libexpat1-dev
cd $ENSEMBL_REPO_ROOT_DIR
cpanm GraphViz
cpanm DBD::SQLite


	# creating a test SQLite database:
cd $ENSEMBL_REPO_ROOT_DIR/ensembl-hive
init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url sqlite:///$ENSEMBL_REPO_ROOT_DIR/ensembl-hive/test_long_mult.sqlite

# Now open Firefox, navigate to http://127.0.0.1:8080/
# and paste in the URL:  sqlite:////home/ensembl/ensembl-api-folder/ensembl-hive/test_long_mult.sqlite
# You should see the pipeline diagram.

db_cmd.pl -url mysql://root:ensembl@localhost/ -sql "CREATE USER 'ens_vm_rw'@'%' IDENTIFIED BY 'ens_vm_password'"
db_cmd.pl -url mysql://root:ensembl@localhost/ -sql "GRANT ALL PRIVILEGES ON *.* TO 'ens_vm_rw'@'%'"

db_cmd.pl -url mysql://root:ensembl@localhost/ -sql "CREATE USER 'ensro'@'%'"
db_cmd.pl -url mysql://root:ensembl@localhost/ -sql "GRANT SELECT, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, SHOW VIEW ON *.* TO 'ensro'@'%'"

	# creating a test MySQL database:
init_pipeline.pl Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf -pipeline_url mysql://ens_vm_rw:ens_vm_password@localhost/ens_vm_rw_long_mult

# Again, open a (new) Firefox tab, navigate to http://127.0.0.1:8080/
# and paste in the URL:  mysql://ens_vm_rw:ens_vm_password@localhost/ens_vm_rw_long_mult
# You should see the pipeline diagram.

	# Add a Unity Launcher icon for a regular Terminal:
newlist=`gsettings get com.canonical.Unity.Launcher favorites | sed 's/]/, \x27application:\/\/gnome-terminal.desktop\x27]/'`
gsettings set com.canonical.Unity.Launcher favorites "$newlist"

	# Create a Desktop icon to navigate the browser to the guiHive server main page:
cat >~/Desktop/guiHive.desktop <<EoF1
[Desktop Entry]
Encoding=UTF-8
Name=guiHive
Type=Link
URL=http://localhost:8080/
Icon=text-html
EoF1

	# Create a Desktop icon to run the guiHive server:
cat >~/Desktop/startGuiHive.desktop <<EoF2
[Desktop Entry]
Name=Start guiHive server
Type=Application
Exec=nohup env PERL5LIB=/home/ensembl/ensembl-api-folder/ensembl-hive/modules PATH=/home/ensembl/src/ensembl-git-tools/bin:/home/ensembl/src/ensembl-git-tools/advanced_bin:/home/ensembl/src/ensembl-variation/C_code:/home/ensembl/src/htslib:/home/ensembl/.plenv/shims:/home/ensembl/.plenv/bin:/home/ensembl/bin:/home/ensembl/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin: PLENV_VERSION=5.14.4 /home/ensembl/ensembl-api-folder/guiHive/server/server &
EoF2
chmod 755 ~/Desktop/startGuiHive.desktop

