
=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Stopwatch

=head1 SYNOPSIS


    my $total_stopwatch    = Bio::EnsEMBL::Hive::Utils::Stopwatch->new()->restart;
    my $fetching_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my $running_stopwatch  = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();

    $fetching_stopwatch->continue();
    $runnable->fetch_input();
    $fetching_stopwatch->pause();
    
    $running_stopwatch->continue();
    $runnable->run();
    $running_stopwatch->pause();

    # ...

    my $only_fetches       = $fetching_stopwatch->get_elapsed;    # probably stopped
    my $total_time_elapsed = $total_stopwatch->get_elapsed;       # running through

=head1 DESCRIPTION

    This is a standalone object used to time various events in the Hive.

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


package Bio::EnsEMBL::Hive::Utils::Stopwatch;

use strict;
use warnings;
use Time::HiRes qw(time);

my $default_unit = 1000;    # milliseconds

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;
    return $self;
}

sub _unit {             # only set it once for each timer to avoid messing everything up
    my $self = shift;

    $self->{'_unit'} = shift if(@_);
    return $self->{'_unit'} || $default_unit;
}

sub is_counting {
    my $self = shift;

    $self->{'_is_counting'} = shift if(@_);
    return $self->{'_is_counting'} || 0;
}

sub accumulated {
    my $self = shift;

    $self->{'_accumulated'} = shift if(@_);
    return $self->{'_accumulated'} || 0;
}

sub continue {
    my $self = shift @_;

    unless($self->is_counting) {    # ignore if it was already running
        $self->is_counting(1);
        $self->{'_start'} = time() * $self->_unit
    }
}

sub restart {
    my $self = shift @_;

    $self->accumulated(0);
    $self->continue;
    return $self;
}

sub get_elapsed {       # peek without stopping (in case it was running)
    my $self = shift @_;

    return ($self->accumulated + $self->is_counting * (time() * $self->_unit - $self->{'_start'}));
}

sub pause {
    my $self = shift @_;

    $self->accumulated( $self->get_elapsed );
    $self->is_counting(0);
}

1;
