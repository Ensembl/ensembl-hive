# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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


use strict;
use warnings;

use Test::More tests => 4;
use Data::Dumper;
use File::Temp qw{tempdir};

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'join_command_args' );
}
#########################

my $dir = tempdir CLEANUP => 1;
chdir $dir;

subtest 'The command line is given as a string' => sub
{
    plan tests => 3;
    is_deeply([join_command_args("ls")], [0,"ls"], "String: the executable name");
    is_deeply([join_command_args("ls cpanfile")], [0,"ls cpanfile"], "String: the executable name and an argument");
    is_deeply([join_command_args("ls | cat")], [0,"ls | cat"], "String: two executables piped");
};

subtest 'The command line is given as an arrayref' => sub
{
    plan tests => 3;
    is_deeply([join_command_args(["ls"])], [0,"ls"], "Array with 1 element: the executable name");
    is_deeply([join_command_args(["ls", "cpanfile"])], [0,"ls cpanfile"], "Array with 2 elements: the executable and an argument");
    is_deeply([join_command_args(["ls", "file space"])], [0,"ls 'file space'"], "Array with 2 elements: the executable and an argument that contains a space");
};

subtest 'The command line is given as an arrayref and contains redirections / pipes' => sub
{
    plan tests => 3;
    is_deeply([join_command_args(["ls", ">", "file space"])], [1, "ls > 'file space'"], "Array with a redirection");
    is_deeply([join_command_args(["ls", "|", "cat"])], [1, "ls | cat"], "Array with a pipe");
    is_deeply([join_command_args(["ls", "|", "cat", ">", "file space"])], [1, "ls | cat > 'file space'"], "Array with a pipe and a redirection");
};

done_testing();
