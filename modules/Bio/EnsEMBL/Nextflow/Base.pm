=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 NAME

 Bio::EnsEMBL::Nextflow::Base;

=cut

package Bio::EnsEMBL::Nextflow::Base;

use strict;
use warnings;
use Data::Dumper;
use Carp;
use JSON;

sub new {
  my $class = shift @_;
  my $args = shift @_;

  my $self = bless {}, $class;
  $self->_init(%{$args});

  return $self;
}

sub _init {
  my ($self, %args) = @_;

  my $defaults = $self->param_defaults();

  while (my ($param_name, $default_value) = each %{$defaults}) {
    if (defined($args{$param_name})) {
      if (ref($default_value) eq 'ARRAY' && ref($args{$param_name}) ne 'ARRAY') {
        my @array = split(",", $args{$param_name});
        $self->param($param_name, \@array);
      } else {
        $self->param($param_name, $args{$param_name});
      }
    } else {
      $self->param($param_name, $default_value);
    }
  }

  while (my ($param_name, $value) = each %args) {
    if (!defined($self->{$param_name})) {
      $self->param($param_name, $value);
    }
  }

  if (defined($self->{'reg_conf'})) {
      require Bio::EnsEMBL::Registry;
      Bio::EnsEMBL::Registry->load_all($self->{'reg_conf'}, undef, undef, undef, 'throw_if_missing');
  }
}

sub fetch_input {
  my $self = shift;

  return 1;
}

sub run {
  my $self = shift;

  return 1;
}

sub write_output {
  my $self = shift;

  return 1;
}

sub param_defaults {
  my $self = shift;

  return {};
}

sub param {
  my ($self, $param_name, $param_value) = @_;

  if (defined($param_value)) {
    $self->{$param_name} = $param_value;
  }

  return $self->{$param_name} || undef;
}

sub param_required {
  my ($self, $param_name) = @_;

  if (!defined($self->{$param_name})) {
    $self->throw("Param $param_name is required and should be defined");
  }

  return $self->param($param_name);
}

sub param_is_defined {
  my ($self, $param_name) = @_;

  if (defined($self->{$param_name})) {
    return 1;
  }

  return 0;
}

sub warning {
  my ($self, $msg) = @_;

  print $msg."\n";
}

sub throw {
  my $msg = pop @_;

  confess "--ERROR-- ".$msg;
}

sub complete_early {
  my ($self, $msg, $branch_code) = @_;

  if (defined($branch_code)) {
    open(my $dataflow_fh, '>>', "dataflow_".$branch_code.".json");
    close($dataflow_fh);
  }

  $msg .= "\n" unless $msg =~ /\n$/;
  die $msg;
}

sub dataflow_output_id {
  my ($self, $args, $branch_code) = @_;

  open(my $dataflow_fh, '>>', "dataflow_".$branch_code.".json");
  my $encoded_args = encode_json($args);
  print $dataflow_fh $encoded_args."\n";
  close($dataflow_fh);
}

sub output {
  my ($self, $output) = @_;

  unless ($self->param_is_defined('_output')) {
    $self->param('_output',[]);
  }

  if ($output) {
    if (ref($output) ne 'ARRAY') {
      $self->throw('Must pass RunnableDB:output an array ref not a '.$output);
    }
    push(@{$self->param('_output')}, @$output);
  }

  return $self->param('_output');
}

1;

