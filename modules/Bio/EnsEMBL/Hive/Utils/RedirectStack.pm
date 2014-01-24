=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::RedirectStack

=head1 DESCRIPTION

    Sometimes there is a need to intercept STDOUT/STDERR and log it in multiple files,
    depending on which of the nested objects is "in control" at the moment.

    In Hive when a Worker is running a job it logs into a job's file, but between jobs it logs into its own file.
    This class implements a convenient stack of proxy file descriptors that lets you log STDOUT or STDERR in various files.

=head1 USAGE EXAMPLE

    use RedirectStack;

    my $rs_stdout = RedirectStack->new(\*STDOUT);

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

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Utils::RedirectStack;

use strict;
use warnings;

sub new {
    my ($class, $fh) = @_;

    die "Please supply filehandle to be redirected as the only argument" unless $fh;

    return bless {
        '_fh'       => $fh,
        '_sp'       => 0,
        '_handle_stack' => [],
    }, $class;
}

sub push {
    my ($self, $filename) = @_;

    die "Please supply filename to be redirected into as the only argument" unless $filename;

    unless($self->{_handle_stack}[$self->{_sp}]) {
        open $self->{_handle_stack}[$self->{_sp}], '>&', $self->{_fh};
    }
    close $self->{_fh};
    open $self->{_fh}, '>', $filename;
    ++$self->{_sp};
}

sub pop {
    my ($self) = @_;

    if($self->{_handle_stack}[$self->{_sp}]) {
        close $self->{_handle_stack}[$self->{_sp}];
        delete $self->{_handle_stack}[$self->{_sp}];
    }
    close $self->{_fh};
    open $self->{_fh}, '>&', $self->{_handle_stack}[--$self->{_sp}];
}

1;

