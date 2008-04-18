#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::SystemCmd

=cut

=head1 SYNOPSIS

my $db      = Bio::EnsEMBL::DBAdaptor->new($locator);
my $runDB   = Bio::EnsEMBL::Hive::RunnableDB::SystemCmd->new ( 
                                                    -db      => $db,
                                                    -input_id   => $input_id
                                                    -analysis   => $analysis );
$runDB->fetch_input(); #reads from DB
$runDB->run();
$runDB->output();
$runDB->write_output(); #writes to DB

=cut

=head1 DESCRIPTION

This object is a very simple module.  It takes the input_id
and runs it as a system command.

=cut

=head1 CONTACT

jessica@ebi.ac.uk

=cut

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Hive::RunnableDB::SystemCmd;

use strict;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;

use Bio::EnsEMBL::Hive::Process;
our @ISA = qw(Bio::EnsEMBL::Hive::Process);


##############################################################
#
# override inherited fetch_input, run, write_output methods
# so that nothing is done
#
##############################################################

sub fetch_input {
  my $self = shift;

  print("input_id\n  ", $self->input_id,"\n");
  $self->{'cmd'} = $self->input_id;

  if($self->input_id =~ /^{/) {
    my $input_hash = eval($self->input_id);
    if($input_hash) {
      $self->{'cmd'} = $input_hash->{'cmd'} if($input_hash->{'cmd'});
      if($input_hash->{'did'}) {
        $self->{'cmd'} = $self->db->get_AnalysisDataAdaptor->fetch_by_dbID($input_hash->{'did'});
      }
    }
  }
  print("cmd\n  ", $self->{'cmd'},"\n");
  return 1;
}

sub run
{
  my $self = shift;
  system($self->{'cmd'}) == 0 or die "system ".$self->{'cmd'}." failed: $?";
  return 1;
}

sub write_output {
  my $self = shift;
  return 1;
}

1;
