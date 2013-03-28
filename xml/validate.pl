#!/usr/bin/env perl

use strict;
use warnings;
use XML::LibXML;

unless(scalar(@ARGV) == 2) {
    die "Usage:\n\t$0 <xml_file> <schema_file.xsd|schema_file.rng>\n";
}

my ($xml_file, $schema_file) = @ARGV;

my $class = ($schema_file=~/.rng$/) ? 'RelaxNG' : 'Schema';

my $schema = "XML::LibXML::$class"->new(location => $schema_file);
my $parser = XML::LibXML->new;

my $dom = $parser->parse_file($xml_file);
eval { $schema->validate( $dom ) };

if($@) {
    print "$class validation failed: $@\n";
} else {
    print "$class validation succeeded\n";
}

