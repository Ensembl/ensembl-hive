
use strict;
use warnings;

use lib 't/lib/';
use Test::More;
use Data::Dumper;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'stringify', 'destringify' );
}
#########################


my $structure = {
    'foo' => 'bar',
    'bar' => 'foobar'
};

my $struct_string = stringify $structure;
ok($struct_string, 'returned a value');
is($struct_string, q!{"bar" => "foobar","foo" => "bar"}!, 'correct representation');


$struct_string = stringify $structure;
ok($struct_string, 'returned a value');
is($struct_string, q!{"bar" => "foobar","foo" => "bar"}!, 'correct representation');

$structure = {
    foo => 'bar',
    latin => {
	lorem => {
	    ipsum => 'dolor',
	},
	atrium => 'foo bar',
    }
};

$Data::Dumper::Maxdepth = 1;
$struct_string = stringify $structure;
ok($structure, 'value returned');
is($struct_string, 
   q!{"foo" => "bar","latin" => {"atrium" => "foo bar","lorem" => {"ipsum" => "dolor"}}}!,
   'correct depth');

done_testing();
