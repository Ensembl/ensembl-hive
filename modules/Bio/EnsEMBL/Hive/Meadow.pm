=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow;

=head1 DESCRIPTION

    Meadow is an abstract interface to the queue manager.

    A Meadow knows how to check&change the actual status of Workers on the farm.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Meadow;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Configurable');


# -------------------------------------- <versioning of the Meadow interface> -------------------------------------------------------

our $MEADOW_MAJOR_VERSION = '2';                # Make sure you change this number whenever an incompatible change is introduced


sub get_meadow_major_version {

    return $MEADOW_MAJOR_VERSION;               # fetch the declared $MEADOW_MAJOR_VERSION of the interface
}


sub get_meadow_version {
    my $self = shift @_;

    return $self->VERSION // 'unversioned';     # fetch the declared $VERSION of a specific Meadow implementation
}


sub check_version_compatibility {
    my $self = shift @_;

    my $mmv = $self->get_meadow_major_version();
    my $mv  = $self->get_meadow_version();
#    warn "$self :  MVC='$mmv', MV='$mv'\n";

    return ($mv=~/^$mmv\./) ? 1 : 0;
}

# -------------------------------------- </versioning of the Meadow interface> ------------------------------------------------------


sub new {
    my ($class, $config) = @_;

    my $self = bless {}, $class;

    $self->config( $config );
    $self->context( [ 'Meadow', $self->type, $self->cached_name ] );

    return $self;
}


sub cached_name {
    my ($self) = @_;

    my $name;

    unless( ref($self) and $name = $self->{'_name'} ) {

        if($name = $self->name() and ref($self) ) {
            $self->{'_name'} = $name;
        }
    }

    return $name;
}


sub type { # should return 'LOCAL' or 'LSF'
    my $class = shift @_;

    $class = ref($class) if(ref($class));

    return (reverse split(/::/, $class ))[0];
}


sub signature {
    my $self = shift @_;

    return $self->type.'/'.$self->cached_name;
}


sub pipeline_name { # if set, provides a filter for job-related queries
    my $self = shift @_;

    if(@_) { # new value is being set (which can be undef)
        $self->{'_pipeline_name'} = shift @_;
    }
    return $self->{'_pipeline_name'};
}


sub job_name_prefix {
    my $self = shift @_;

    return ($self->pipeline_name() ? $self->pipeline_name().'-' : '') . 'Hive-';
}


sub job_array_common_name {
    my ($self, $rc_name, $iteration) = @_;

    return $self->job_name_prefix() ."${rc_name}-${iteration}";
}


sub responsible_for_worker {
    my ($self, $worker) = @_;

    return ($worker->meadow_type eq $self->type) && ($worker->meadow_name eq $self->cached_name);
}


sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}


sub kill_worker {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}


sub parse_report_source_line {
    my $self = shift @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}

=head2 get_report_entries_for_process_ids
    Title   :  get_report_entries_for_process_ids
    Function:  A higher-level method that gets process_ids as input and
               returns a structure like parse_report_source_line.
=cut

sub get_report_entries_for_process_ids {
    my ($self, @process_ids) = @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}

sub get_report_entries_for_time_interval {
    my $self = shift @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}

1;
