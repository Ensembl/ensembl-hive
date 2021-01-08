#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long qw(:config pass_through no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'load_file_or_module');


main();


sub main {

    my $self    = {};
    my $tweaks  = [];

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc=i'             => \$self->{'nosqlvc'},     # using "=i" instead of "!" for consistency with scripts where it is a propagated option

        'tweak|SET=s@'          => \$tweaks,
        'DELETE=s'              => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'#'; },
        'SHOW=s'                => sub { my ($opt_name, $opt_value) = @_; push @$tweaks, $opt_value.'?'; },

        'h|help'                => \$self->{'help'},
    ) or die "Error in command line arguments\n";

    if (@ARGV) {
        die "ERROR: There are invalid arguments on the command-line: ". join(" ", @ARGV). "\n";
    }

    if($self->{'help'}) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    my $pipeline;

    if($self->{'url'} or $self->{'reg_alias'}) {
        $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

    } else {
        pod2usage({-exitvalue => 0, -verbose => 2});

    }

    if(@$tweaks) {
        my $need_write = $pipeline->apply_tweaks( $tweaks );
        if ($need_write) {
            $pipeline->save_collections();
        }
    }

}


__DATA__

=pod

=head1 NAME

    tweak_pipeline.pl

=head1 SYNOPSIS

    ./tweak_pipeline.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_file> -reg_alias <reg_alias> ] -tweak 'analysis[mafft%].analysis_capacity=undef'

=head1 DESCRIPTION

    This is a script to "tweak" attributes or parameters of an existing Hive pipeline.

=head1 OPTIONS

B<--url>

    url defining where hive database is located

B<--reg_conf>

    path to a Registry configuration file

B<--reg_type>

    Registry type of the Hive DBAdaptor

B<--reg_alias>

    species/alias name for the Hive DBAdaptor

B<--nosqlvc>

    "No SQL Version Check" - set this to one if you want to force working with a database created by a potentially schema-incompatible API (0 by default)

B<--tweak>

    An assignment command that performs one individual "tweak". You can "tweak" global/analysis parameters, analysis attributes and resource classes:

        -tweak 'pipeline.param[take_time]=20'                   # override a value of a pipeline-wide parameter; can also create a non-existent parameter
        -tweak 'analysis[take_b_apart].param[base]=10'          # override a value of an analysis-wide parameter; can also create a non-existent parameter
        -tweak 'analysis[add_together].analysis_capacity=undef' # override a value of an analysis attribute
        -tweak 'analysis[add_together].batch_size=15'           # override a value of an analysis_stats attribute
        -tweak 'analysis[part_multiply].resource_class=urgent'  # set the resource class of an analysis (whether a resource class with this name existed or not)
        -tweak 'resource_class[urgent].LSF=-q yesteryear'       # update or create a new resource description

    If multiple "tweaks" are requested, they will be performed in the given order.

B<--DELETE>

    Shortcut to delete a parameter

B<--SHOW>

    Shortcut to show a parameter value

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

