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

use Test::More;
use Test::Warn;
use Data::Dumper;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::URL' );
}

#------------------------------------[OLD & NEW]---------------------------------------------------

{       # OLD+NEW style mysql DB URL:
    my $url = 'mysql://user:password@hostname:3306/databasename';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'mysql',         'driver correct' );
    is( $url_hash->{'user'},   'user',          'user correct' );
    is( $url_hash->{'pass'},   'password',      'password correct' );
    is( $url_hash->{'host'},   'hostname',      'hostname correct' );
    is( $url_hash->{'port'},   3306,            'port number correct' );
    is( $url_hash->{'dbname'}, 'databasename',  'database name correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # OLD+NEW style simple sqlite URL:
    my $url = 'sqlite:///databasename';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',       'driver correct' );
    is( $url_hash->{'dbname'}, 'databasename', 'database name correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # OLD+NEW style degenerate analysis URL (just the analysis name)
    my $url = 'this_analysis_name';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is_deeply( $url_hash, { 'unambig_url'   => ':///', 'query_params'  => { 'object_type' => 'Analysis', 'logic_name' => 'this_analysis_name' } },  'simple analysis name correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

#------------------------------------[OLD]---------------------------------------------------

{       # OLD style local table URL:
    my $url = ':////final_result';

    my $url_hash;
    warning_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        qr/The URL '.*' only works with the old parser/,
        'Warned the user';

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'final_result'}, 'query_params hash correct' );
}

{       # OLD style (local) accu URL:
    my $url = ':////accu?partial_product={digit}';

    my $url_hash;
    warning_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        qr/The URL '.*' only works with the old parser/,
        'Warned the user';

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'Accumulator', 'accu_name' => 'partial_product', 'accu_address' => '{digit}' },
                                            'query_params hash correct' );
}

{       # OLD style foreign analysis URL:
    my $url = 'mysql://who:secret@where.co.uk:12345/other_pipeline/analysis?logic_name=foreign_analysis';

    my $url_hash;
    warnings_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        [
            qr/NEW URL parser thinks you are using the OLD URL syntax for a remote Analysis, so skipping it/,
            qr/The URL '.*' only works with the old parser/,
        ],
        'Warned the user';

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      'other_pipeline',                                   'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'Analysis', 'logic_name' => 'foreign_analysis' }, 'query_params hash correct' );
}

{       # OLD style foreign table URL (due to mysql/pgsql database/table naming rules, should stay in OLD format only)
    my $url = 'pgsql://user:password@hostname/databasename/foreign_table';

    my $url_hash;
    warnings_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        [
            qr/NEW URL parser thinks you are using the OLD URL syntax for a remote NakedTable, so skipping it/,
            qr/The URL '.*' only works with the old parser/,
        ],
        'Warned the user';

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'pgsql',                     'driver correct' );
    is( $url_hash->{'user'},   'user',                      'user correct' );
    is( $url_hash->{'pass'},   'password',                  'password correct' );
    is( $url_hash->{'host'},   'hostname',                  'hostname correct' );
    is( $url_hash->{'port'},   undef,                       'port number correctly missing' );
    is( $url_hash->{'dbname'}, 'databasename',              'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'foreign_table' }, 'query_params hash correct' );
}

{       # OLD style sqlite foreign table URL (due to the 'insertion_method' parameter defined, should stay in OLD format only)
    my $url = 'sqlite:///databasename/foreign_table?insertion_method=REPLACE';

    my $url_hash;
    warnings_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        [
            qr/NEW URL parser thinks you are using the OLD URL syntax for a remote NakedTable, so skipping it/,
            qr/The URL '.*' only works with the old parser/,
        ],
        'Warned the user';


    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',                    'driver correct' );
    is( $url_hash->{'dbname'}, 'databasename',              'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'foreign_table', 'insertion_method' => 'REPLACE' }, 'query_params hash correct' );
}

#------------------------------------[NEW]---------------------------------------------------

{       # NEW style full path sqlite URL:
    my $url = 'sqlite:///path/to/database_name.sqlite';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',                        'driver correct' );
    is( $url_hash->{'dbname'}, 'path/to/database_name.sqlite',  'database path correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # NEW style local table URL:
    my $url = '?table_name=final_result';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'final_result' }, 'query_params hash correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # NEW style accu URL:
    my $url = '?accu_name=intermediate_results&accu_address={digit}&accu_input_variable=partial_product';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is_deeply( $url_hash->{'query_params'}, {
            'object_type'           => 'Accumulator',
            'accu_name'             => 'intermediate_results',
            'accu_address'          => '{digit}',
            'accu_input_variable'   => 'partial_product',
    }, 'query_params hash correct' );
    ## The order of keys is not deterministic, so little hope of getting the same order back, skipping:
    # is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # NEW style registry DB URL:
    my $url = 'registry://core@homo_sapiens/~/work/ensembl-compara/scripts/pipeline/production_reg_conf.pl';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'registry',                                                          'registry driver correct' );
    is( $url_hash->{'user'},   'core',                                                              'registry type correct' );
    is( $url_hash->{'host'},   'homo_sapiens',                                                      'registry alias correct' );
    is( $url_hash->{'dbname'}, '~/work/ensembl-compara/scripts/pipeline/production_reg_conf.pl',    'registry filename correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}


{       # NEW style foreign analysis URL:
    my $url = 'mysql://who:secret@where.co.uk:12345/other_pipeline?logic_name=foreign_analysis';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      'other_pipeline',                                   'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'Analysis', 'logic_name' => 'foreign_analysis' }, 'query_params hash correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}


{       # NEW style foreign table URL:
    my $url = 'mysql://who:secret@where.co.uk:12345/other_pipeline?table_name=foreign_table';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      'other_pipeline',                                   'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'foreign_table' }, 'query_params hash correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}


{       # NEW style foreign table URL with a two-part path:
    my $url = 'sqlite:///other_directory/other_pipeline?table_name=foreign_table';

    my $url_hash;
    warning_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        qr/OLD URL parser thinks you are using the NEW URL syntax for a remote NakedTable/,
        'Warned the user';

    ok($url_hash, "parser returned something for $url");

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'sqlite',                                           'driver correct' );
    is( $url_hash->{'dbname'},      'other_directory/other_pipeline',                   'database path correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'foreign_table' }, 'query_params hash correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

#------------------------------------[COLLISION!]---------------------------------------------------

{       # OLD style sqlite foreign table URL  ...or... NEW style bipartite sqlite path
    my $url = 'sqlite:///databasename/foreign_table';

    my $url_hash;
    warning_like
        {$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url ) }
        qr/The URL '.*' can be parsed ambiguously/,
        'Warned the user';

    ok($url_hash, "parser returned something for $url");

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',                    'driver correct' );
    is( $url_hash->{'dbname'}, 'databasename',              'database name correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'NakedTable', 'table_name' => 'foreign_table' }, 'query_params hash correct' );
}


{       # NEW style database server URL (db_name-less) with a trailing slash:
    my $url = 'mysql://who:secret@where.co.uk:12345/';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      '',                                                 'database name correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # NEW style database server URL (db_name-less) without a trailing slash:
    my $url = 'mysql://who:secret@where.co.uk:12345';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      undef,                                              'database name correct' );

    # hash_to_url can't tell whether the original url had a slash or not,
    # arbitrarily chooses to leave off the slash when reconstructing from hash components
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url . '/', 'hash_to_url returns original url');
}

{       # NEW style sqlite URL with an absolute path:
    my $url = 'sqlite:////var/folders/1k/qdbfbdls6nn98pqzbdkcsnfc0000gn/T/eR81O_qhbH/ehive_server_pipeline_db?logic_name=part_multiply';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',       'driver correct' );
    is( $url_hash->{'dbname'}, '/var/folders/1k/qdbfbdls6nn98pqzbdkcsnfc0000gn/T/eR81O_qhbH/ehive_server_pipeline_db', 'database path correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'Analysis', 'logic_name' => 'part_multiply' }, 'query params correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

{       # NEW style sqlite URL with a relative path:
    my $url = 'sqlite:///relative/path/to/ehive_server_pipeline_db?logic_name=part_multiply';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',       'driver correct' );
    is( $url_hash->{'dbname'}, 'relative/path/to/ehive_server_pipeline_db', 'database path correct' );
    is_deeply( $url_hash->{'query_params'}, { 'object_type' => 'Analysis', 'logic_name' => 'part_multiply' }, 'query params correct' );
    is( Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($url_hash), $url, 'hash_to_url returns original url');
}

done_testing();
