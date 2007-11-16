#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::Test

=cut

=head1 SYNOPSIS

my $db      = Bio::EnsEMBL::DBAdaptor->new($locator);
my $repmask = Bio::EnsEMBL::Hive::RunnableDB::Dummy->new ( 
                                                    -db      => $db,
                                                    -input_id   => $input_id
                                                    -analysis   => $analysis );
$repmask->fetch_input(); #reads from DB
$repmask->run();
$repmask->output();
$repmask->write_output(); #writes to DB

=cut

=head1 DESCRIPTION

This object is used to test failure of jobs in the hive system.

It is intended for development purposes only!!

It parses the analysis.parameters and analysis_job.input_id as
(string representing) hasrefs and extracts the divisor and the value.
If the modulo (value % divisor) is 0, the job will fail.

=cut

=head1 CONTACT

ensembl-dev@ebi.ac.uk

=cut

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Hive::RunnableDB::Test;

use strict;

use Bio::EnsEMBL::Hive::Process;
our @ISA = qw(Bio::EnsEMBL::Hive::Process);


=head2 fetch_input

  Implementation of the Bio::EnsEMBL::Hive::Process interface

=cut

sub fetch_input {
  my $self = shift;
  $self->get_params($self->parameters);
  $self->get_params($self->input_id);

  return 1;
}


=head2 run

  Implementation of the Bio::EnsEMBL::Hive::Process interface

=cut

sub run
{
  my $self = shift;
  my $divisor = $self->divisor();
  my $value = $self->value();
  if (!$divisor or !defined($value)) {
    die "Wrong parameters: divisor = $divisor and value = $value\n";
  } elsif ($value % $divisor == 0) {
    die "$value % $divisor is 0 => die!\n";
  }
  return 1;
}


=head2 write_output

  Implementation of the Bio::EnsEMBL::Hive::Process interface

=cut

sub write_output {
  my $self = shift;
  return 1;
}


=head2 divisor

  Arg [1]     : (optional) $divisor
  Example     : $object->divisor($divisor);
  Example     : $divisor = $object->divisor();
  Description : Getter/setter for the divisor attribute
  Returntype  : 
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub divisor {
  my $self = shift;
  if (@_) {
    $self->{_divisor} = shift;
  }
  return $self->{_divisor};
}


=head2 value

  Arg [1]     : (optional) $value
  Example     : $object->value($value);
  Example     : $value = $object->value();
  Description : Getter/setter for the value attribute
  Returntype  : 
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub value {
  my $self = shift;
  if (@_) {
    $self->{_value} = shift;
  }
  return $self->{_value};
}


=head2 get_params

=cut

sub get_params {
  my $self         = shift;
  my $param_string = shift;

  return unless($param_string);
  print("parsing parameter string : ",$param_string,"\n");

  my $params = eval($param_string);
  return unless($params);

  if(defined($params->{'divisor'})) {
    $self->divisor($params->{'divisor'});
  }
  if(defined($params->{'value'})) {
    $self->value($params->{'value'});
  }
}

1;
