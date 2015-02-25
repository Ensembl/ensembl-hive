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

my ($url, $url_hash);

$url = 'mysql://user:password@hostname:3306/databasename';

$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

ok($url_hash, 'parsing returned something');
isa_ok( $url_hash, 'HASH' );

is( $url_hash->{'driver'}, 'mysql', 'driver correct' );
is( $url_hash->{'user'},   'user',  'user correct' );
is( $url_hash->{'pass'},   'password', 'password correct' );
is( $url_hash->{'host'},   'hostname', 'hostname correct' );
is( $url_hash->{'port'},   3306,           'port number correct' );
is( $url_hash->{'dbname'}, 'databasename', 'database name correct' );


$url = 'sqlite:///databasename';

$url_hash = Bio::EnsEMBL::Hive::Utils::URL::parse( $url );

ok($url_hash, 'parsing returned something');
isa_ok( $url_hash, 'HASH' );

is( $url_hash->{'driver'}, 'sqlite',       'driver correct' );
is( $url_hash->{'dbname'}, 'databasename', 'database name correct' );


done_testing();
