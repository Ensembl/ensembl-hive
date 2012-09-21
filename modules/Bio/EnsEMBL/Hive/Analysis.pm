=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::Analysis

=head1 SYNOPSIS

=head1 DESCRIPTION

    An Analysis object represents a "stage" of the Hive pipeline that groups together
    all jobs that share the same module and the same common parameters.

    Individual Jobs are said to "belong" to an Analysis.

    Control rules unblock when their condition Analyses are done.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::Analysis;

use strict;
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'

use base (  'Bio::EnsEMBL::Storable',       # inherit dbID(), adaptor() and new() methods
         );
 

sub new {
    my $class = shift @_;

    my $self = $class->SUPER::new( @_ );    # deal with Storable stuff

    my ($logic_name, $module, $parameters, $resource_class_id) =
         rearrange([qw(logic_name module parameters resource_class_id) ], @_);

    $self->logic_name($logic_name)                  if($logic_name);
    $self->module($module)                          if($module);
    $self->parameters($parameters)                  if($parameters);
    $self->resource_class_id($resource_class_id)    if($resource_class_id);

    return $self;
}


sub logic_name {
    my $self = shift @_;

    $self->{'_logic_name'} = shift @_ if(@_);

    return $self->{'_logic_name'};
}


sub module {
    my $self = shift @_;

    $self->{'_module'} = shift @_ if(@_);

    return $self->{'_module'};
}


sub parameters {
    my $self = shift @_;

    $self->{'_parameters'} = shift @_ if(@_);

    return $self->{'_parameters'};
}


sub resource_class_id {
    my $self = shift @_;

    $self->{'_resource_class_id'} = shift @_ if(@_);

    return $self->{'_resource_class_id'};
}


=head2 process

  Arg [1]    : none
  Example    : $process = $analysis->process;
  Description: construct a Process object from the $analysis->module name
  Returntype : Bio::EnsEMBL::Hive::Process subclass 
  Exceptions : none
  Caller     : general

=cut

sub process {
    my $self = shift;

    my $process_class = $self->module
                     or die "Analysis '".$self->logic_name."' does not have its 'module' defined";

    if($process_class!~/::/) {
        $process_class = 'Bio::EnsEMBL::Hive::Runnable::'.$process_class;
    }

    my $file = $process_class;
    $file =~ s/::/\//g;
    require "${file}.pm";

    my $process_object = $process_class->new(
                                -db       => $self->adaptor->db,
                                -input_id => '1',
                                -analysis => $self,
                                );

    return $process_object;
}


=head2 url

  Arg [1]    : none
  Example    : $url = $analysis->url;
  Description: Constructs a URL string for this database connection
               Follows the general URL rules.
  Returntype : string of format
               mysql://<user>:<pass>@<host>:<port>/<dbname>/analysis?logic_name=<name>
  Exceptions : none
  Caller     : general

=cut

sub url {
    my $self = shift;

    return undef unless($self->adaptor);

    return $self->adaptor->db->dbc->url . '/analysis?logic_name=' . $self->logic_name;
}


=head2 stats

  Arg [1]    : none
  Example    : $stats = $analysis->stats;
  Description: returns the AnalysisStats object associated with this Analysis
               object.  Does not cache, but pull from database by using the
               Analysis objects adaptor->db.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub stats {
    my $self = shift;

    # Not cached internally since we want it to always be in sync with the database.
    # Otherwise the user application would need to be aware of the sync state and send explicit 'sync' calls.

    my $stats = $self->adaptor->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id($self->dbID);
    return $stats;
}


sub toString {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(dbID logic_name module parameters) ));
}

1;

