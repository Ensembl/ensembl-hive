=pod 

=head1 NAME

Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN -input_id_list '[{"a"=>1},{"a"=>2}]' -debug 1

=head1 DESCRIPTION

    Runnable that takes a list of input_ids ("input_id_list"), removes some elements from it that are dataflown to branch #2
    whilst the remainder of the list is dataflown is dataflown to branch #1.  Several things can be parametrized: the number
    of elements taken from the list (on each end) and to which branch they are flown.
    The Runnable makes sense in the Bio::EnsEMBL::Hive::Examples::Factories::PipeConfig::FoldLeft_conf where we can recursively
    consume the list one element at a time and compute something along the way.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users
    to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Examples::Factories::RunnableDB::GrabN;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');


sub param_defaults {
    return {
        'grab_n_left'       => 1,   # How many elements to take from the left-end of the list ("shift")
        'grab_n_right'      => 0,   # How many elements to take from the right-end of the list ("pop")
        'fan_branch_code'   => 2,   # On which branch flow the elements
    }
}

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                    This reads the list of hash "input_id_list" and extracts as many elements as requested (following the "grab_n_left" and
                    "grab_n_right" parameters) and push them to the "output_ids" array parameter. This represents the input_ids of the jobs
                    to be created.

=cut

sub fetch_input {
    my $self = shift @_;

    my $input_id_list   = $self->param_required('input_id_list');
    my $grab_n_left     = $self->param_required('grab_n_left');
    my $grab_n_right    = $self->param_required('grab_n_right');

    die "Negative values are not allowed for 'grab_n_left'\n" if $grab_n_left < 0;
    die "Negative values are not allowed for 'grab_n_right'\n" if $grab_n_right < 0;

    my @output_ids;
    if ($grab_n_left+$grab_n_right <= scalar(@$input_id_list)) {
        push @output_ids, splice(@$input_id_list, 0, $grab_n_left);
        push @output_ids, splice(@$input_id_list, -$grab_n_right, $grab_n_right);

    } else {
        # Take the whole list
        @output_ids = @$input_id_list;
        @$input_id_list = ();
    }

    $self->param('output_ids', \@output_ids);
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                    This flows all the elements (hashes) of "output_ids" to the branch refered by "fan_branch_code" (default #2)
                    It then flows to branch #1 the remainder of the list, and a "_list_exhausted" flag that tells whether the list is now empty or not.

=cut

sub write_output {
    my $self = shift @_;

    my $output_ids      = $self->param_required('output_ids');
    my $input_id_list   = $self->param_required('input_id_list');
    my $fan_branch_code = $self->param_required('fan_branch_code');

    # Fan out the jobs (if any)
    $self->dataflow_output_id($output_ids, $fan_branch_code) if @$output_ids;

    # Collector job. This dataflow replaces the autoflow
    $self->dataflow_output_id({'_list_exhausted' => !scalar(@$input_id_list), 'input_id_list' => $input_id_list}, 1);
}

1;

