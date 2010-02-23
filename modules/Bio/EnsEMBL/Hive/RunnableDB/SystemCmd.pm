#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::SystemCmd

=head1 DESCRIPTION

This RunnableDB module acts as a wrapper for shell-level command lines.

It supports three different modes:

1) Command line is stored in the 'input_id' field of the analysis_job table.
    (only works with command lines shorter than 255 bytes).
    Most people tend to use it not realizing there are other possiblities.

2) Command line is stored in the input_id() or parameters() as the value corresponding to the 'cmd' key.
    A better way as it also allows other parameters to be passed in.

3) A numeric key to the analysis_data table (where the actual command line is stored)
    is kept in the input_id() or parameters() as the value corresponding to the 'did' key. This allows to overcome the 255 byte limit.
    Well, if you REALLY couldn't fit your command line into 250~ish bytes, are you sure you can manage big pipelines?
    Just joking :)

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::SystemCmd;

use strict;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub strict_hash_format {    # we must allow non-strict hash format
    return 0;
}

sub fetch_input {
    my $self = shift;

        # First, FIND the command line
        #
    my $cmd = ($self->input_id()!~/^\{.*\}$/)
            ? $self->input_id()                 # assume the command line is given in input_id
            : $self->param('cmd')               # or defined as a hash value (in input_id or parameters)
    or $self->param('did')                      # or referred to the analysis_data table where longer strings can be stored
            ? $self->db->get_AnalysisDataAdaptor->fetch_by_dbID( $self->param('did') )
            : die "Could not find the command defined in input_id(), param('cmd') or param('did')";

        # Store the value with parameter substitutions for the actual execution:
        #
    $self->param('cmd', $self->param_substitute($cmd));
}

sub run {
    my $self = shift;

    my $cmd = $self->param('cmd');

    if(my $return_value = system($cmd)) {
        $return_value >>= 8;
        die "system( $cmd ) failed: $return_value";
    }

    return 1;
}

sub write_output {
    my $self = shift;

    return 1;
}

1;
