
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::Dummy

=head1 SYNOPSIS

This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
and is ran by Workers during the execution of eHive pipelines.
It is not generally supposed to be instantiated and used outside of this framework.

Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

A job of 'Bio::EnsEMBL::Hive::RunnableDB::Dummy' analysis does not do any work by itself,
but it benefits from the side-effects that are associated with having an analysis.

For example, if a dataflow rule is linked to the analysis then
every job that is created or flown into this analysis will be dataflown further according to this rule.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::Dummy;

use strict;
use base ('Bio::EnsEMBL::Hive::Process');

=head2 fetch_input

    Title:    fetch_input
    Function: Overrides the standard fetch_input() interface method so that nothing is done

=cut

sub fetch_input {
  my $self = shift;
  $self->db->dbc->disconnect_when_inactive(0);
}

=head2 run

    Title:    run
    Function: Overrides the standard run() interface method so that nothing is done

=cut

sub run {
}

=head2 write_output

    Title:    write_output
    Function: Overrides the standard write_output() interface method so that nothing is done

=cut

sub write_output {
}

1;
