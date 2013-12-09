=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::Dummy

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{}"

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{take_time=>3}"

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{take_time=>'rand(3)+1'}"

=head1 DESCRIPTION

    A job of 'Bio::EnsEMBL::Hive::RunnableDB::Dummy' analysis does not do any work by itself,
    but it benefits from the side-effects that are associated with having an analysis.

    For example, if a dataflow rule is linked to the analysis then
    every job that is created or flown into this analysis will be dataflown further according to this rule.

    param('take_time'):     How much time to spend sleeping (floating point seconds);
                            can be given by a runtime-evaluated formula; useful for testing.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::Dummy;

use strict;
use warnings;
use Time::HiRes ('usleep');

use base ('Bio::EnsEMBL::Hive::Process');


sub strict_hash_format { # allow this Runnable to parse parameters in its own way (don't complain)
    return 0;
}

=head2 param_defaults

    Description : Implements param_defaults() interface method of Bio::EnsEMBL::Hive::Process that defines module defaults for parameters.

=cut

sub param_defaults {

    return {
        'take_time' => 0,   # how much time run() method will spend in sleeping state
    };
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

    my $take_time = eval $self->param('take_time');
    if($take_time) {
        print "Sleeping for '$take_time' seconds...\n";
        usleep( $take_time*1000000 );
        print "Done.\n";
    }
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we simply override this method so that nothing is done.

=cut

sub write_output {
}

1;
