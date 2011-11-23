package Bio::EnsEMBL::Hive::Utils::Graph::Config;

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Utils::Graph::Config

=head1 SYNOPSIS

  my $c = Bio::EnsEMBL::Hive::Utils::Graph::Config->new();
  $c->merge({
    Colours => {
      Status => {
        BLOCKED => 'magenta'
      }
    },
    DisplayDetails => 0
  });

=head1 DESCRIPTION

This module holds the configuration used for generating images with the
Graph object in hive. The aim is to provide a set of default values
which can be overriden via the C<merge()> subroutine.

=head1 AVAILABLE OPTIONS

=over 8

=item B<Colours> B<Status>

  Colours => { Status => { READY => 'magenta' } }

Allows you to set a colour for every status available in hive. See
L<http://www.graphviz.org/doc/info/attrs.html#k:color> for information about
the available colours.

=item B<Colours> B<Flows>

  Colours => { Flows => { data => 'magenta' } }

Allows you to colour the flow lines. Keys available are I<data> and I<control>.
See
L<http://www.graphviz.org/doc/info/attrs.html#k:color> for information about
the available colours.

=item B<Fonts>

  Fonts => { node => 'serif' }

Allows you to control the fonts used in the image. Keys available are 
I<node> and I<edge>. See
L<http://www.graphviz.org/doc/info/attrs.html#d:fontname> for information about
the available font types.

=item B<DisplayDetails>

  DisplayDetails => 1
  
Writes information into the graph to denote the user and the database name 
this hive was run under.

=back

=head1 METHODS/SUBROUTINES

See inline

=head1 AUTHOR

$Author: lg4 $

=head1 VERSION

$Revision: 1.2 $

=cut

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Argument qw(rearrange);
use Bio::EnsEMBL::Utils::Scalar qw(assert_ref);

=pod

=head2 new()

  Arg [CONFIG] :  Hash to be passed into the C<merge()> method
  Returntype : Config object
  Exceptions : If the parameters are not as required
  Status     : Beta
  
=cut

sub new {
  my ($class, @args) = @_;
  my $self = bless($class->_default(), ref($class) || $class);
  my ($config) = rearrange([qw(config)], @args);
  $self->merge($config) if defined $config;
  return $self;
}

sub _default {
  my ($class) = @_;
  return {
    Colours => {
      Status => {
        BLOCKED     => 'grey',
        LOADING     => 'yellow',
        SYNCHING    => 'yellow',
        READY       => 'yellow',
        WORKING     => 'yellow',
        ALL_CLAIMED => 'yellow',
        DONE        => 'green',
        FAILED      => 'red',
        OTHER       => 'white',
        TABLE       => 'black',
      },
      Flows => {
        data       => 'blue',
        control    => 'red',
        semablock  => 'red',
      }
    },
    Fonts => {
      node => 'Helvetica',
      edge => 'Helvetica',
    },
    DisplayDetails => 1
  };
}

=head2 merge()

  Arg[1] : The hash to merge into this hash
  Returntype : None
  Exceptions : If the given reference was not a hash
  Status : Beta
  
=cut

sub merge {
  my ($self, $incoming) = @_;
  assert_ref($incoming, 'HASH');
  %{$self} = (%{$self}, %{$incoming});
  return;
}

1;
