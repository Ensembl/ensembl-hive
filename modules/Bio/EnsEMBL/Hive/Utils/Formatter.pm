=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Formatter

=head1 DESCRIPTION

    An output printer and formatter
    Modes:
    onfly - immediate print of data, no storage
    json - prints only json passed to function, no any debug-level control, text print also skipped
    custom_output - uses custom function to print formatted text


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


package Bio::EnsEMBL::Hive::Utils::Formatter;

use strict;
use warnings;
use JSON;
use Bio::EnsEMBL::Hive::Utils ('throw');


sub new {
  my $class = shift @_;
  my $self = bless {}, $class;
  $self->{mode}->{onfly} = 0;
  $self->{mode}->{text} = 1;
  $self->{mode}->{json} = 0;
  $self->{mode}->{error} = 1;
  $self->{mode}->{warning} = 1;
  $self->{mode}->{info} = 1;

  return $self;
}

sub set_mode {
  my ($self, $mode, $value) = @_;
  $self->{mode}->{$mode} = $value;
}

sub stack_output {
  my ($self, $output) = @_;
  if ($self->{mode}->{onfly} == 1) {
    $self->{output} = [];
    push @{$self->{output}},$output;
    $self->print_data();
  } else {
    push @{$self->{output}},$output;
  }
}

sub add_warning {
  my ($self, $warning) = @_;
  $self->stack_output({msg => $warning, type => 'warning'});
}


sub add_error {
  my ($self, $error) = @_;
  $self->stack_output({msg => $error, type => 'error'});
}

sub add_info {
  my ($self, $info) = @_;
  $self->stack_output({msg => $info, type => 'info'});
}

sub add_custom_output {
  my ($self, $info, $type, $function) = @_;
  $self->stack_output({msg => $info, type => $type, function => $function});
}

sub add_infoHash {
  my ($self, $info) = @_;
  $self->{infoHash} = $info;
  if ($self->{mode}->{onfly} == 1) {
    $self->print_data();
  }
}

sub print_data {
  my ($self) = @_;

  if ($self->{mode}->{json} == 1) {
    my $json = JSON->new->allow_nonref;
    print $json->encode($self->{infoHash});
    return;
  }

  if ($self->{mode}->{text} == 1) {
    foreach my $text (@{$self->{output}}) {
      my $type = $text->{type};
      if ($self->{mode}->{$type} == 1) {
        if ($text->{function}){
          my @params = @{ $text->{msg} };
          $text->{function}->(@params);
        } else {
          print $text->{msg};
          print "\n";
        }
      }
    }
  }

}


1;
