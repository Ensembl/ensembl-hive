# A Meadow is an abstract interface for one of several implementations of Workers' process manager.
#
# A Meadow knows how to check&change the actual status of Workers

package Bio::EnsEMBL::Hive::Meadow;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Configurable');


sub new {
    my ($class, $config) = @_;

    my $self = bless {}, $class;

    $self->config( $config );
    $self->context( [ 'Meadow', $self->type, $self->name ] );

    return $self;
}


sub type { # should return 'LOCAL' or 'LSF'
    my $class = shift @_;

    $class = ref($class) if(ref($class));

    return (reverse split(/::/, $class ))[0];
}


sub signature {
    my $self = shift @_;

    return $self->type.'/'.$self->name;
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


sub generate_job_name {
    my ($self, $worker_count, $iteration, $rc_name) = @_;

    return $self->job_name_prefix()
        ."${rc_name}-${iteration}"
        . (($worker_count > 1) ? "[1-${worker_count}]" : '');
}


sub responsible_for_worker {
    my ($self, $worker) = @_;

    return ($worker->meadow_type eq $self->type) && ($worker->meadow_name eq $self->name);
}


sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}


sub kill_worker {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}

1;
