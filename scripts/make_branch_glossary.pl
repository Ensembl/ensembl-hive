#!/usr/bin/env perl

use strict;
use warnings;

use File::Temp qw/tempfile/;
use Getopt::Long;
use HTML::Entities;
use List::Util qw(min);

#use Bio::EnsEMBL::Hive::Version;
use Bio::EnsEMBL::Hive::Utils::Config;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

my $ehrd        = $ENV{'EHIVE_ROOT_DIR'}        or die "Environment variable 'EHIVE_ROOT_DIR' not defined, please check your setup";
chdir $ehrd.'/docs';

my $pipeconfig_template = q{
package %s;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

sub pipeline_analyses {
    my ($self) = @_;
    my $all_analyses = [%s];
    map {$_->{-module} = 'Bio::EnsEMBL::Hive::RunnableDB::Dummy'} @$all_analyses;
    return $all_analyses;
}

1;

};

my $display_config_json = q{
{
    "Graph": {"Pad": 0} 
}
};

die "Usage: $0 <base_filename> <title>\n" unless scalar(@ARGV)==2;
main(@ARGV);



sub main {

    my ($base_filename, $title) = @_;

    my $diagrams = generate_diagrams($base_filename);
    my $data     = {'title' => $title, 'diagrams' => $diagrams};

    # The HTML file
    open(my $fh, '>', $base_filename.'.html') or die "Couldn't open the output file";
    generate_html($fh, $data);
    close($fh);

    # The Markdown file
    open($fh, '>', $base_filename.'.md') or die "Couldn't open the output file";
    generate_markdown($fh, $data);
    close($fh);

    # The RST file
    open($fh, '>', $base_filename.'.rst') or die "Couldn't open the output file";
    generate_rst($fh, $data);
    close($fh);
}

sub generate_diagrams {

    my $base_filename = shift;

    # Creates a temporary JSON config file
    my ($fh, $json_filename) = tempfile(UNLINK => 1);
    print STDERR "json: $json_filename\n";
    print $fh $display_config_json;
    close($fh);
    my @confs = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
    push @confs, $json_filename;

    # Creates a temporary pipe-config file
    my ($pipe_fh, $pipe_filename) = tempfile('tXXXXXXX', UNLINK => 1, DIR => '.', SUFFIX => '.pm');
    my $package_name = File::Basename::basename($pipe_filename);
    $package_name =~ s/\.pm//;
    print STDERR "pipeconfig: $pipe_filename\n";
    close($pipe_fh);

    # The example files
    my @example_files = glob($base_filename.'/*.txt');
    my @data = sort {$a->[0] <=> $b->[0]} map {[parse_one_file($_)]} @example_files;
    my @diagrams;

    foreach my $record (@data) {
        unless ($record->[3]) {
            push @diagrams, [@$record];
            next;
        }

        # Write the pipeconfig file
        open(my $pipe_fh, '>', $pipe_filename);
        print $pipe_fh sprintf($pipeconfig_template, $package_name, $record->[3]);
        close($pipe_fh);

        # The diagram
        warn $record->[0];
        my $img = sprintf('%s/%d.png', $base_filename, $record->[0]);
        system($ehrd.'/scripts/generate_graph.pl', -pipeconfig => $pipe_filename, -output => $img, -pipeline_name => '', map {-config_file => $_} @confs);
        push @diagrams, [@$record, $img];
    }
    return \@diagrams;
}

sub parse_one_file {
    my $file_name = shift;
    open(my $fh, '<', $file_name) or die "Couldnt open file [$file_name]";
    my $data;
    {
        local $/ = undef;
        $data = <$fh>;
    }
    close($fh);
    my ($title, $description, $code) = split( /^--*-$/m,  $data);
    chomp $title;
    $title =~ s/^\R*//;
    chomp $description;
    $description =~ s/^\R*//;
    die "Wrong format in '$data'" unless $title and $description;
    if ($code) {
        chomp $code;
        $code =~ s/^\R*//;
    }
    my $id = $file_name;
    $id =~ s/[^0-9]//g;
    return ($id, $title, $description, $code);
}

sub generate_html {
    my ($output_fh, $data) = @_;

    print $output_fh "<html><body><h1>".$data->{'title'}."</h1>\n";
    print $output_fh "<ol>\n";
    my $in_group = 0;
    foreach my $record (@{$data->{'diagrams'}}) {
        if ($record->[3]) {
            print $output_fh sprintf(q{<li><a href="#%d">%s</a></li>}, $record->[0], $record->[1]), "\n";
        } else {
            if ($in_group) {
                print $output_fh q{</ol></li>}, "\n";
            }
            print $output_fh sprintf(q{<li><a href="#%d">%s</a><ol>}, $record->[0], $record->[1]), "\n";
            $in_group = 1;
        }
    }
    if ($in_group) {
        print $output_fh q{</ol></li>}, "\n";
    }

    print $output_fh "</ol><table>\n";
    foreach my $record (@{$data->{'diagrams'}}) {
        if ($record->[3]) {
            print $output_fh sprintf(q{<tr id="%d"><td><h3>%s</h3><p>%s</p><pre>%s</pre></td><td><img src='%s'></td></tr>},
                $record->[0],
                $record->[1],
                $record->[2],
                encode_entities($record->[3]),
                $record->[4],
            ), "\n";
        } else {
            print $output_fh sprintf(q{<tr id="%d"><td><h2>%s</h2><p>%s</p></td><td></td></tr>},
                $record->[0],
                $record->[1],
                $record->[2],
            ), "\n";
        }
    }
    print $output_fh "</table></body></html>\n";
}

sub generate_markdown {
    my ($output_fh, $data) = @_;

    print $output_fh "# ".$data->{'title'}."\n\n";
    print $output_fh "## Index\n\n";
    my $i = 1;
    my $j = 1;
    foreach my $record (@{$data->{'diagrams'}}) {
        if ($record->[3]) {
            print $output_fh sprintf("  %s. [%s](#%s)  \n", chr(96+$j), $record->[1], $record->[0]);
            $j++;
        } else {
            print $output_fh sprintf("%d. [%s](#%s)  \n", $i, $record->[1], $record->[0]);
            $j = 1;
            $i++;
        }
    }
    print $output_fh "\n";
    foreach my $record (@{$data->{'diagrams'}}) {
        if ($record->[3]) {
            print $output_fh sprintf("### <a name='%s'></a>%s\n\n%s\n\n```\n%s\n```\n![diagram](%s)\n", 
                $record->[0],
                $record->[1],
                $record->[2],
                $record->[3],
                $record->[4],
            ), "\n";
        } else {
            print $output_fh sprintf("## <a name='%s'></a>%s\n\n%s\n\n", 
                $record->[0],
                $record->[1],
                $record->[2],
            ), "\n";
        }
    }
}

sub _rst_underline {
    my ($str, $char) = @_;
    return $str . "\n" . ($char x length($str)) . "\n\n";
}

sub generate_rst {
    my ($output_fh, $data) = @_;

    print $output_fh _rst_underline($data->{'title'}, '=');
    print $output_fh "\n";
    foreach my $record (@{$data->{'diagrams'}}) {
        if ($record->[3]) {
            print $output_fh _rst_underline($record->[1], '~');
            print $output_fh $record->[2], "\n\n";
            my $s = $record->[3];
            $s =~ s/^/    /gms;
            print $output_fh "::\n\n", $s, "\n\n";
            print $output_fh ".. figure:: ", $record->[4], "\n\n";
        } else {
            print $output_fh _rst_underline($record->[1], '-');
            print $output_fh $record->[2], "\n\n";
        }
    }
}


__DATA__

=pod

=head1 NAME

scripts/make_branch_glossary.pl

=head1 DESCRIPTION

    An internal eHive script for regenerating the document that lists all (most ?) of the dataflow patterns.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

