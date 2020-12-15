#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
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

use Data::Dumper;

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_url_or_die make_hive_db run_sql_on_db);

# eHive needs this to initialize the pipeline (and run db_cmd.pl)
use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my $pipeline_url = get_test_url_or_die();
my $dbc = make_hive_db($pipeline_url);

# Minimal pipeline on which we can create jobs
my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(-url => $pipeline_url, -no_sql_schema_version_check => 1);
my ($rc) = $pipeline->add_new_or_update('ResourceClass', name => 'res');
my ($analysis1) = $pipeline->add_new_or_update('Analysis', logic_name => 'first', module => 'Mod', resource_class => $rc);
my ($analysis2) = $pipeline->add_new_or_update('Analysis', logic_name => 'second', module => 'Mod', resource_class => $rc);
$pipeline->save_collections;
my $job_adaptor = $pipeline->hive_dba->get_AnalysisJobAdaptor;
my $semaphore_adaptor = $pipeline->hive_dba->get_SemaphoreAdaptor;

sub _assert_store_nested_semaphores {
    my ($title, $semaphore_hash, $expected_jobs, $expected_semaphores, $min_job_id, $min_semaphore_id, $emitting_job, $controlled_semaphore) = @_;

    # Store the jobs and the semaphores
    $job_adaptor->store_nested_semaphores($semaphore_hash, $emitting_job, $controlled_semaphore);

    # Fetch the jobs that have been stored
    my $jobs = $job_adaptor->fetch_all("job_id >= $min_job_id");
    my @job_fields = qw(dbID analysis_id prev_job_id input_id param_id_stack accu_id_stack controlled_semaphore_id);
    my @got_jobs;
    foreach my $job (sort {$a->dbID <=> $b->dbID} @$jobs) {
        push @got_jobs, [map {$job->$_} @job_fields];
    }

    # Fetch the semaphores that have been stored
    my $semaphores = $semaphore_adaptor->fetch_all("semaphore_id >= $min_semaphore_id");
    my @semaphore_fields = qw(dbID local_jobs_counter dependent_job_id);
    my @got_semaphores;
    foreach my $semaphore (sort {$a->dbID <=> $b->dbID} @$semaphores) {
        push @got_semaphores, [map {$semaphore->$_} @semaphore_fields];
    }

    # Check that the jobs and the semaphores are correct
    subtest $title => sub {
        is_deeply(\@got_jobs, $expected_jobs, 'The jobs were correctly stored and linked')
            or diag Dumper(\@got_jobs);
        is_deeply(\@got_semaphores, $expected_semaphores, 'The semaphores were correctly stored and linked')
            or diag Dumper(\@got_semaphores);
    };
}

subtest 'store_nested_semaphores' => sub {

    _assert_store_nested_semaphores(
        'Single job with no semaphore',
		{
			'analysis'  => $analysis1,
			'input_id'  => {'alpha' => 1},
		}, [
            # 1 job created
			[1, 1, undef, '{"alpha" => 1}', '', '', undef],
        ], [
            # No semaphores
        ],
        1, 1,
    );

    _assert_store_nested_semaphores(
        'Depth 1, all jobs belonging to the same analysis',
		{
			'analysis'  => $analysis1,
			'input_id'  => {'alpha' => 2},
            'required_jobs' => [
                {
                    'analysis'  => $analysis1,
                    'input_id'  => {'beta' => 21},
                },
                {
                    'analysis'  => $analysis1,
                    'input_id'  => {'beta' => 22},
                },
            ],
		}, [
            # 3 jobs created
			[2, 1, undef, '{"alpha" => 2}', '', '', undef],
			[3, 1, undef, '{"beta" => 21}', '', '', 1],
			[4, 1, undef, '{"beta" => 22}', '', '', 1],
        ], [
            # 1 semaphore created
            [1, 2, 2],
        ],
        2, 1,
    );

    _assert_store_nested_semaphores(
        'Depth 2, mixed analyses',
		{
			'analysis'  => $analysis1,
			'input_id'  => {'alpha' => 3},
            'required_jobs' => [
                {
                    'analysis'  => $analysis2,
                    'input_id'  => {'beta' => 31},
                    'required_jobs' => [
                        {
                            'analysis'  => $analysis1,
                            'input_id'  => {'gamma' => 311},
                        },
                        {
                            'analysis'  => $analysis1,
                            'input_id'  => {'gamma' => 312},
                        },
                        {
                            'analysis'  => $analysis1,
                            'input_id'  => {'gamma' => 313},
                        },
                    ],
                },
                {
                    'analysis'  => $analysis1,
                    'input_id'  => {'beta' => 32},
                },
            ],
		}, [
            # 6 jobs created
			[5, 1, undef, '{"alpha" => 3}', '', '', undef],
			[6, 2, undef, '{"beta" => 31}', '', '', 2],
			[7, 1, undef, '{"gamma" => 311}', '', '', 3],
			[8, 1, undef, '{"gamma" => 312}', '', '', 3],
			[9, 1, undef, '{"gamma" => 313}', '', '', 3],
			[10, 1, undef, '{"beta" => 32}', '', '', 2],
        ], [
            # 2 semaphores created
            [2, 2, 5],
            [3, 3, 6],
        ],
        5, 2,
    );

    my $emitting_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
        'analysis'          => $analysis2,
        'hive_pipeline'     => $pipeline,
        'input_id'          => {},
        'param_id_stack'    => '100',
        'accu_id_stack'     => '101',
    );

    _assert_store_nested_semaphores(
        'Single job but with an emitting_job',
		{
			'analysis'  => $analysis1,
			'input_id'  => {'alpha' => 4},
		}, [
            # 1 job created
			[11, 1, undef, '{"alpha" => 4}', '100', '101', undef],
        ], [
            # No new semaphores
        ],
        11, 4,
        $emitting_job,
    );

    _assert_store_nested_semaphores(
        'Single job in an existing semaphore and with an emitting_job',
		{
			'analysis'  => $analysis1,
			'input_id'  => {'alpha' => 5},
		}, [
            # 1 job created
			[12, 1, undef, '{"alpha" => 5}', '100', '101', 3],
        ], [
            # The semaphore should have been topped-up
            [3, 4, 6],
        ],
        12, 3,
        $emitting_job,
        $semaphore_adaptor->fetch_by_dbID(3), # Reuse an existing semaphore
    );
};

$dbc->disconnect_if_idle();
run_sql_on_db($pipeline_url, 'DROP DATABASE');

done_testing();

