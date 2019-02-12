#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use Test::More;
use Data::Dumper;
use Test::JSON;
use JSON qw(decode_json);

use Capture::Tiny ':all';
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker beekeeper get_test_url_or_die run_sql_on_db tweak_pipeline);


# eHive needs this to initialize the pipeline (and run db_cmd.pl)
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();

# Starting a first set of checks with a "GCPct" pipeline

init_pipeline('Bio::EnsEMBL::Hive::Examples::SystemCmd::PipeConfig::AnyCommands_conf', $pipeline_url);

my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeline_url );

my @tweak_requests = ();

#Check pipeline.param (show, delete, set)
push @tweak_requests,  ["-SET" => "pipeline.param[take_time]=20", "-json"];
push @tweak_requests,  ["-SHOW" => "pipeline.param[take_time]", "-json"];
push @tweak_requests,  ["-DELETE" => "pipeline.param[take_time]", "-json"];

#Check pipeline (show, set, error)
push @tweak_requests,  ["-tweak" => "pipeline.hive_use_param_stack=20", "-json"];
push @tweak_requests,  ["-tweak" => "pipeline.hive_use_param_stack?", "-json"];
push @tweak_requests,  ["-tweak" => "pipeline.hive_use_param_stac?", "-json"];

#Check analysis (show, delete, set) / (resource_class / is_excluded / error)
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].resource_class?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].resource_class=20", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].resource_class#", "-json"];

push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].is_excluded?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].is_excluded=20", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].is_excluded#", "-json"];

push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].some_wrong_attr?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].some_wrong_attr=20", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].some_wrong_attr#", "-json"];

#Check analysis.wait_for (show, delete, set)
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].wait_for=perform_cmd", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].wait_for?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].wait_for#", "-json"];

#Check analysis.flow_into (show, delete, set)
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].flow_into=perform_cmd", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].flow_into?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].flow_into#", "-json"];

#Check analysis.param (show, delete, set)
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].param[base]=10", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].param[base]?", "-json"];
push @tweak_requests,  ["-tweak" => "analysis[perform_cmd].param[base]#", "-json"];

#Check resource_class (show, set, error)
push @tweak_requests,  ["-tweak" => "resource_class[urgent].LSF=-q yesteryear", "-json"];
push @tweak_requests,  ["-tweak" => "resource_class[urgent].LSF?", "-json"];

foreach my $request (@tweak_requests) {
    my $stdout = capture_stdout {
        tweak_pipeline($pipeline_url, $request);
    };
    is_valid_json $stdout;
    my $stdoutJson = decode_json($stdout);
    use Data::Dumper;
    ok(scalar @{$stdoutJson->{Tweaks}} > 0, "Tweaks responce recieved for " . join (' ', @{$request}) . Dumper($stdoutJson->{Tweaks}));
    foreach my $tweakJson (@{$stdoutJson->{Tweaks}}) {
        ok($tweakJson->{Object}->{Type} eq "Pipeline" ||
            $tweakJson->{Object}->{Type} eq "Analysis" ||
            $tweakJson->{Object}->{Type} eq "Resource class",
            'Object type is correct for ' . join (' ', @{$request}));

        ok($tweakJson->{Error} ||
            $tweakJson->{Action} eq "SET" ||
            $tweakJson->{Action} eq "SHOW" ||
            $tweakJson->{Action} eq "DELETE",
            'Action field is correct for ' . join (' ', @{$request}));

        ok(exists ($tweakJson->{Object}->{Id}), 'Id field exists for' . join (' ', @{$request}));
        ok(exists ($tweakJson->{Object}->{Name}), 'Name field exists for' . join (' ', @{$request}));
        ok(exists ($tweakJson->{Return}->{OldValue}) || $tweakJson->{Error}, 'Old value exists for ' . join (' ', @{$request}));
        ok(exists($tweakJson->{Return}->{NewValue}) || $tweakJson->{Error}, 'New value exists for ' . join (' ', @{$request}));
        ok($tweakJson->{Return}->{Field} || $tweakJson->{Error}, 'Field exists for ' . join (' ', @{$request}));
    };
}

done_testing();
