
package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;

use Exporter;
use Carp qw{croak};


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( spurt );

our $VERSION = '0.00';

sub spurt {
    my ($content, $path) = @_;
    croak qq{Can't open file "$path": $!} unless open my $file, '>', $path;
    croak qq{Can't write to file "$path": $!}
    unless defined $file->syswrite($content);
    return $content;
}


1;
