#!/usr/bin/env perl

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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

use Test::More tests => 8;

use Cwd 'getcwd';
use Capture::Tiny ':all';
use File::Temp qw{tempdir};

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::RedirectStack' );
}
#########################

my $dir = tempdir CLEANUP => 1;
my $original = getcwd;
chdir $dir;

my $rs_stdout = Bio::EnsEMBL::Hive::Utils::RedirectStack->new(\*STDOUT);
my $stdout = capture_stdout {
    print "Message 1\n";            # gets displayed on the screen
    $rs_stdout->push('foo');
        print "Message 2\n";            # goes to 'foo'
        $rs_stdout->push('bar');
            print "Message 3\n";            # goes to 'bar'
            system('echo subprocess A');    # it works for subprocesses too
            $rs_stdout->pop;
        print "Message 4\n";            # goes to 'foo'
        system('echo subprocess B');    # again, works for subprocesses as well
        $rs_stdout->push('baz');
            print "Message 5\n";            # goest to 'baz'
            $rs_stdout->pop;
        print "Message 6\n";            # goes to 'foo'
        $rs_stdout->pop;
    print "Message 7\n";            # gets displayed on the screen
};

is($stdout, qq{Message 1\nMessage 7\n}, 'stdout output');
ok(-e 'foo', '"foo" exists');
is(`cat foo`, qq{Message 2\nMessage 4\nsubprocess B\nMessage 6\n}, 'foo output');
ok(-e 'bar', '"bar" exists');
is(`cat bar`, qq{Message 3\nsubprocess A\n}, 'bar output');
ok(-e 'baz', '"bar" exists');
is(`cat baz`, qq{Message 5\n}, 'baz output');

done_testing();

chdir $original;

