#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

use Test::Exception;
use Test::More;

use Bio::EnsEMBL::Hive::Utils qw(stringify);
use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline get_test_urls);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $ehive_test_pipeline_urls = get_test_urls();

my $different_param_hash;


## Test that dataflow_output_id creates a job with the expected fields
sub test_dataflow {
    my ($job, $output_ids, $expected_input_id, $expected_param_id_stack) = @_;

    # First reset the job's parameters (_unsubstituted_param_hash and _param_hash)
    # NOTE: $different_param_hash allows simulating a job whose parameter
    # hash has been changed since being initialized to its input_id
    $job->param_init($different_param_hash // $job->input_id);

    subtest sprintf('Test %s%s dataflowing %s', $job->input_id, $different_param_hash ? sprintf("->".stringify($different_param_hash)) : '', stringify($output_ids)), sub {
        my $new_job_ids = $job->dataflow_output_id($output_ids, 1);
        is(scalar(@$new_job_ids), 1, 'Created a job');

        if (scalar(@$new_job_ids)) {
            my $new_job = $job->adaptor->fetch_by_dbID($new_job_ids->[0]);
            ok($new_job, 'Fetched the new job');

            is($new_job->input_id, $expected_input_id, 'Correct input_id');

            $expected_param_id_stack //= '';
            is($new_job->param_id_stack, $expected_param_id_stack, 'Correct param_id_stack');

            $job->adaptor->remove_all('job_id = '.$new_job_ids->[0]);
        }
    };
}


## Test that dataflow_output_id refuses to create a job
sub test_dataflow_fail {
    my ($job, $output_ids) =@_;

    # First reset the job's parameters
    $job->param_init($job->input_id);
    throws_ok { $job->dataflow_output_id($output_ids, 1) } qr/is not a hashref ! Cannot dataflow/, sprintf('Dataflowing %s is not allowed', stringify($output_ids));
}


## Example values used throughout the tests
my $snow_input_id           = {"snow" => 27};
my $snow_input_id_str       = stringify($snow_input_id);
my $a_input_id              = {"a" => 58};
my $a_input_id_str          = stringify($a_input_id);
my $a_mult_input_id         = {"a_multiplier" => 58};
my $a_mult_input_id_str     = stringify($a_mult_input_id);
my $fresh_a_mult_input_id   = {"a_multiplier" => 27};
my $fresh_a_input_id_str    = stringify({"a" => 27});
my $missing_a_input_id_str  = stringify({"a" => undef});
my $default_a_input_id_str  = stringify({"a" => '9650156169'});
my $template_const          = stringify({"a" => 34});
my $template_var            = stringify({"a" => "#a_multiplier#"});


## Test all the possible scalar types
## NOTE: this assumes the stacks are turned off and there is no template
sub test_dataflow_scalars {
    my ($job) = @_;

    # When flowing undef, a job is creating with the input_id of the emitter
    test_dataflow($job, undef,          $job->input_id);
    test_dataflow($job, [undef],        $job->input_id);
    test_dataflow($job, 'undef',        $job->input_id);
    test_dataflow($job, '[undef]',      $job->input_id);
    test_dataflow($job, '["undef"]',    $job->input_id);

    # The only allowed scalars are hashref, arrayref of hashrefs, or strings representing those
    test_dataflow_fail($job, 34);
    test_dataflow_fail($job, [[]]);
    test_dataflow_fail($job, [34]);
    test_dataflow_fail($job, '34');
    test_dataflow_fail($job, '[[]]');
    test_dataflow_fail($job, '[34]');
    test_dataflow_fail($job, '');
    test_dataflow_fail($job, sub {});
    test_dataflow_fail($job, \*STDOUT);

    # Empty hash in various forms
    test_dataflow($job, {},         '{}');
    test_dataflow($job, '{}',       '{}');
    test_dataflow($job, '[{}]',     '{}');
    test_dataflow($job, '["{}"]',   '{}');

    # Non-empty hash in various forms
    test_dataflow($job, $snow_input_id,             $snow_input_id_str);
    test_dataflow($job, $snow_input_id_str,         $snow_input_id_str);
    test_dataflow($job, "[$snow_input_id_str]",     $snow_input_id_str);
    test_dataflow($job, "['$snow_input_id_str']",   $snow_input_id_str);
}


sub test_all_dataflows_without_stack {
    my ($job1, $job2) = @_;

    # 1. the emitting job has a non-empty input_id
    # When flowing undef, a job is creating with the input_id of the emitter
    test_dataflow($job1, undef, $job1->input_id);
    # Even if the value of a parameter has been changed at runtime
    $different_param_hash = $fresh_a_mult_input_id;
    test_dataflow($job1, undef, $job1->input_id);
    undef $different_param_hash;

    # When flowing a hash, the hash is stringified regardless of its content
    test_dataflow($job1, {}, '{}');
    test_dataflow($job1, $snow_input_id, $snow_input_id_str);

    # 2. the emitting job has an empty input_id
    # When flowing undef, a job is creating with the input_id of the emitter
    test_dataflow($job2, undef, $job2->input_id);
    # Even if the parameter hash is not empty
    $different_param_hash = $fresh_a_mult_input_id;
    test_dataflow($job2, undef, $job2->input_id);
    undef $different_param_hash;

    # When flowing a hash, the hash is stringified regardless of its content
    test_dataflow($job2, {}, '{}');
    test_dataflow($job2, $snow_input_id, $snow_input_id_str);
}

sub test_all_dataflows_with_stack {
    my ($job1, $job2) = @_;

    # 1. the emitting job has a non-empty input_id
    # When flowing undef, a job is creating with an empty-hash input_id and the stack populated
    test_dataflow($job1, undef, '{}', 1);
    # Even if the value of a parameter has been changed at runtime
    $different_param_hash = $fresh_a_mult_input_id;
    test_dataflow($job1, undef, '{}', 1);
    undef $different_param_hash;

    # When flowing a hash, the hash is stringified and the stack populated
    test_dataflow($job1, {}, '{}', 1);
    test_dataflow($job1, $snow_input_id, $snow_input_id_str, 1);

    # 2. the emitting job has an empty input_id
    # When flowing undef, a job is creating with an empty-hash input_id and no stack needs to be populated
    test_dataflow($job2, undef, '{}');
    # Even if the parameter hash is not empty
    $different_param_hash = $fresh_a_mult_input_id;
    test_dataflow($job2, undef, '{}');
    undef $different_param_hash;

    # When flowing a hash, the hash is stringified and no stack needs to be populated
    test_dataflow($job2, {}, '{}');
    test_dataflow($job2, $snow_input_id, $snow_input_id_str);
}

sub test_all_dataflows_with_const_template {
    my ($job1, $job2, $with_stack) = @_;

    # Since the template does not depend on any variables, it will become
    # the input_id regardless of what is dataflown and the original input_id
    # The stack is only populated when the emitting job has an non-empty input_id
    test_dataflow($job1, undef,          $template_const, $with_stack);
    test_dataflow($job1, {},             $template_const, $with_stack);
    test_dataflow($job1, $snow_input_id, $template_const, $with_stack);
    test_dataflow($job1, $a_input_id,    $template_const, $with_stack); # Trying this one because both hashes have the same key "a"
    test_dataflow($job2, undef,          $template_const);
    test_dataflow($job2, {},             $template_const);
    test_dataflow($job2, $snow_input_id, $template_const);
    test_dataflow($job2, $a_input_id,    $template_const);  # Trying this one because both hashes have the same key "a"
}

sub test_all_dataflows_with_var_template {
    my ($job1, $job2, $with_stack) = @_;

    # 1. the emitting job has a non-empty input_id, so the stack will be populated if requested
    # All the output dataflows follow the template
    # When flowing anything that doesn't have a_multiplier, a_multiplier comes from the emitter's input_id
    test_dataflow($job1, undef,                     $default_a_input_id_str, $with_stack);
    test_dataflow($job1, {},                        $default_a_input_id_str, $with_stack);
    test_dataflow($job1, $snow_input_id,            $default_a_input_id_str, $with_stack);

    # When flowing something that has a_multiplier, the value is used
    test_dataflow($job1, $a_mult_input_id,          $a_input_id_str, $with_stack);
    test_dataflow($job1, $a_mult_input_id_str,      $a_input_id_str, $with_stack);

    {
        # Templates are evaluated using the freshest values. Here we set a
        # param hash that is different from the input_id and we expect the
        # same value to be flown out unless overriden in the output_id
        $different_param_hash = $fresh_a_mult_input_id;
        test_dataflow($job1, undef,                 $fresh_a_input_id_str, $with_stack);
        test_dataflow($job1, {},                    $fresh_a_input_id_str, $with_stack);
        test_dataflow($job1, $a_mult_input_id,      $a_input_id_str, $with_stack);
        undef $different_param_hash;
    }

    # 2. the emitting job has an empty input_id, so the stack won't be populated
    # When flowing anything that doesn't have a_multiplier, a_multiplier remains undefined
    test_dataflow($job2, undef,                     $missing_a_input_id_str);
    test_dataflow($job2, {},                        $missing_a_input_id_str);
    test_dataflow($job2, $snow_input_id,            $missing_a_input_id_str);

    # When flowing something that has a_multiplier, the value is used
    test_dataflow($job2, $a_mult_input_id,          $a_input_id_str);
    test_dataflow($job2, $a_mult_input_id_str,      $a_input_id_str);

    {
        # Templates are evaluated using the freshest values. Here we set a
        # param hash that is different from the input_id and we expect the
        # same value to be flown out unless overriden in the output_id
        $different_param_hash = $fresh_a_mult_input_id;
        test_dataflow($job2, undef,                 $fresh_a_input_id_str);
        test_dataflow($job2, {},                    $fresh_a_input_id_str);
        test_dataflow($job2, $a_mult_input_id,      $a_input_id_str);
        undef $different_param_hash;
    }
}



foreach my $pipeline_url (@$ehive_test_pipeline_urls) {

    subtest 'Test on '.$pipeline_url, sub {
        #plan tests => 17;

        init_pipeline('Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf', $pipeline_url);
        my $pipeline    = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                        => $pipeline_url,
            -disconnect_when_inactive   => 1,
        );
        my $hive_dba    = $pipeline->hive_dba;
        my $job_a       = $hive_dba->get_AnalysisJobAdaptor;
        my $dt          = $pipeline->collection_of('DataflowTarget')->find_one_by('to_analysis_url' => 'add_together');
        my $job1        = $job_a->fetch_by_dbID(1);
        my $job2        = $job_a->fetch_by_dbID(2);

        # Empty the input_id of the second job to test that scenario as well
        $job2->input_id('{}');

        subtest 'No template', sub {
            # Make sure we start with no template
            $dt->input_id_template(undef);

            subtest 'No stacks', sub {
                $pipeline->hive_use_param_stack(0);
                $dt->extend_param_stack(0);
                test_dataflow_scalars($job1);
                test_all_dataflows_without_stack($job1, $job2);
                ok(1);
            };

            subtest 'Stack enabled globally', sub {
                $pipeline->hive_use_param_stack(1);
                $dt->extend_param_stack(0);
                test_all_dataflows_with_stack($job1, $job2);
                ok(1);
            };

            subtest 'Stack enabled for this dataflow', sub {
                $pipeline->hive_use_param_stack(0);
                $dt->extend_param_stack(1);
                test_all_dataflows_with_stack($job1, $job2);
                ok(1);
            };

            subtest 'All stacks enabled', sub {
                $pipeline->hive_use_param_stack(1);
                $dt->extend_param_stack(1);
                test_all_dataflows_with_stack($job1, $job2);
                ok(1);
            };
        };

        # And now add a template
        subtest 'Constant template (no variables involved)', sub {
            $dt->input_id_template($template_const);

            subtest 'No stacks', sub {
                $pipeline->hive_use_param_stack(0);
                $dt->extend_param_stack(0);
                test_all_dataflows_with_const_template($job1, $job2);
                ok(1);
            };

            subtest 'With stack', sub {
                $pipeline->hive_use_param_stack(1);
                $dt->extend_param_stack(0);
                test_all_dataflows_with_const_template($job1, $job2, 1);
                ok(1);
            };
        };

        subtest 'Variable template (depends on a variable)', sub {
            $dt->input_id_template($template_var);

            subtest 'No stacks', sub {
                $pipeline->hive_use_param_stack(0);
                $dt->extend_param_stack(0);
                test_all_dataflows_with_var_template($job1, $job2);
                ok(1);
            };

            subtest 'With stack', sub {
                $pipeline->hive_use_param_stack(1);
                $dt->extend_param_stack(0);
                test_all_dataflows_with_var_template($job1, $job2, 1);
                ok(1);
            };
        };

    }
}

done_testing();

