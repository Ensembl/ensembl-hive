=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::AttemptAdaptor

=head1 DESCRIPTION

    Module to encapsulate all db access for class Attempt.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::AttemptAdaptor;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Attempt;

use base ('Bio::EnsEMBL::Hive::DBSQL::ObjectAdaptor');

# ----------------------------- ObjectAdaptor implementation -----------------------------------

sub default_table_name {
    return 'attempt';
}


sub object_class {
    return 'Bio::EnsEMBL::Hive::Attempt';
}


# ------------------------------------ Attempt methods ------------------------------------------

=head2 check_in_attempt

  Arg [1]    : Bio::EnsEMBL::Hive::Attempt $attempt
  Arg [2]    : Boolean $finalize_attempt. Whether this is the last update of the attempt
  Arg [2]    : Boolean $is_success: whether the attempt has successfully reached its end
  Description: When $is_success is passed, the method understands this is the last update
               and will finalize the attempt entry, writing end time and statistics such
               as runtime_msec and query_count.

=cut

sub check_in_attempt {
    my ($self, $attempt, $is_success) = @_;

    my $attempt_id = $attempt->dbID;

    my $sql = "UPDATE attempt SET ";

    if (defined $is_success) {
        $sql .= "status='END'";
        $sql .= ",when_updated=CURRENT_TIMESTAMP";
        $sql .= ",when_ended=CURRENT_TIMESTAMP";
        $sql .= ",is_success=$is_success";
        $sql .= ",runtime_msec=".($attempt->runtime_msec//'NULL');
        $sql .= ",query_count=".($attempt->query_count//'NULL');
    } else {
        $sql .= "status='".$attempt->status."'";
        $sql .= ",when_updated=CURRENT_TIMESTAMP";
    }

    $sql .= " WHERE attempt_id='$attempt_id' ";

    $self->dbc->do($sql);
}


=head2 record_attempt_interruption

  Arg [1]    : Integer $attempt_id. Valid dbID of an attempt
  Description: Update the attempt table to mark this attempt as done but failed.

=cut

sub record_attempt_interruption {
    my ($self, $attempt_id) = @_;

    # Note that we don't update "when_updated" to keep a trace of the
    # last ping from the job
    my $sql = "UPDATE attempt SET ";
      $sql .= "status='END'";
      $sql .= ",when_ended=CURRENT_TIMESTAMP";
      $sql .= ",is_success=0";
      $sql .= " WHERE attempt_id='$attempt_id' ";

    $self->dbc->do($sql);
}


=head2 store_out_files

  Arg [1]    : Bio::EnsEMBL::Hive::Attempt $attempt
  Description: update locations of log files, if present
  Returntype : Boolean: whether the attempt has been updated in the database or not
  Exceptions : None
  Caller     : Bio::EnsEMBL::Hive::Worker

=cut

sub store_out_files {
    my ($self, $attempt) = @_;

    return $self->update_stdout_file_AND_stderr_file($attempt);
}


1;

