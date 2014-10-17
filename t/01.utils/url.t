
use strict;
use warnings;

use lib 't/lib/';
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
