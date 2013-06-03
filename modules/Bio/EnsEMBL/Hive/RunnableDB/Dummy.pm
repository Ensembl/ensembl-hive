
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

param('take_time'):     How much time to spend sleeping (seconds); useful for testing

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::Dummy;

use strict;
use base ('Bio::EnsEMBL::Hive::Process');

sub strict_hash_format { # allow this Runnable to parse parameters in its own way (don't complain)
    return 0;
}

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here we simply override this method so that nothing is done.

=cut

sub fetch_input {
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Since this Runnable is a Dummy, it does nothing. But it can also optionally sleep for param('take_time') seconds.

=cut

sub run {
    my $self = shift @_;

    sleep( $self->param('take_time') );
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we simply override this method so that nothing is done.

=cut

sub write_output {
}

1;
