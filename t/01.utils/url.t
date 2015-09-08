#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::URL' );
}
#########################

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
}

{       # OLD style foreign table URL (will be parsed differently now!) :
    my $url = 'pgsql://user:password@hostname:3306/databasename/foreign_table';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'pgsql',                     'driver correct' );
    is( $url_hash->{'user'},   'user',                      'user correct' );
    is( $url_hash->{'pass'},   'password',                  'password correct' );
    is( $url_hash->{'host'},   'hostname',                  'hostname correct' );
    is( $url_hash->{'port'},   3306,                        'port number correct' );
    is( $url_hash->{'dbname'}, 'databasename/foreign_table','database name correct' );
}

{       # OLD+NEW style simple sqlite URL:
    my $url = 'sqlite:///databasename';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',       'driver correct' );
    is( $url_hash->{'dbname'}, 'databasename', 'database name correct' );
}

{       # NEW style full path sqlite URL:
    my $url = 'sqlite:///path/to/database_name.sqlite';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'}, 'sqlite',                        'driver correct' );
    is( $url_hash->{'dbname'}, 'path/to/database_name.sqlite',  'database path correct' );
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
}

{       # OLD style local table URL:
    my $url = ':////final_result';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'table_name'}, 'final_result', 'table name correct' );
}

{       # OLD style accu URL:
    my $url = ':////accu?partial_product={digit}';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'table_name'},  'accu',             'accu correct' );
    is( $url_hash->{'tparam_name'}, 'partial_product',  'accu variable name correct' );
    is( $url_hash->{'tparam_value'},'{digit}',          'accu signature correct' );
}

{       # NEW style local table URL:
    my $url = '?table_name=final_result';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'query_part'},  'table_name=final_result',                  'query_part correct' );
    is_deeply( $url_hash->{'query_params'}, { 'table_name' => 'final_result' }, 'query_params hash correct' );
}

{       # NEW style foreign analysis URL:
    my $url = 'mysql://who:secret@where.co.uk:12345/other_pipeline?analysis_name=foreign_analysis';

    my $url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

    ok($url_hash, "parser returned something for $url");
    isa_ok( $url_hash, 'HASH' );

    is( $url_hash->{'driver'},      'mysql',                                            'driver correct' );
    is( $url_hash->{'user'},        'who',                                              'user correct' );
    is( $url_hash->{'pass'},        'secret',                                           'password correct' );
    is( $url_hash->{'host'},        'where.co.uk',                                      'hostname correct' );
    is( $url_hash->{'port'},         12345,                                             'port number correct' );
    is( $url_hash->{'dbname'},      'other_pipeline',                                   'database name correct' );
    is( $url_hash->{'query_part'},  'analysis_name=foreign_analysis',                   'query_part correct' );
    is_deeply( $url_hash->{'query_params'}, { 'analysis_name' => 'foreign_analysis' },  'query_params hash correct' );
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
    is( $url_hash->{'query_part'},  'table_name=foreign_table',                         'query_part correct' );
    is_deeply( $url_hash->{'query_params'}, { 'table_name' => 'foreign_table' },        'query_params hash correct' );
}

done_testing();
