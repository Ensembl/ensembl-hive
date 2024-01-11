#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2024] EMBL-European Bioinformatics Institute
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
use Bio::EnsEMBL::Hive::Utils qw(whoami);
use Bio::EnsEMBL::Hive::Utils::Test qw(get_test_urls);

BEGIN {
  use_ok( 'Bio::EnsEMBL::Hive::Utils::Test' );
}

# no EHIVE_TEST_PIPELINE_URLS set

local $ENV{'EHIVE_TEST_PIPELINE_URLS'} = undef;

my $urls = get_test_urls();
is(scalar(@$urls), 1, 
   "with no test_pipeline_urls returns one default url");
like($$urls[0], qr/^sqlite:\/\/\//,
   "with no test_pipeline_urls returns correct default sqlite url");

$urls = get_test_urls(-driver => 'mysql');
is(scalar(@$urls), 0, "no url returned for an unavailable driver");

$urls = get_test_urls(-tag => 'TAP');
is(scalar(@$urls), 1, 
   "with no test_pipeline_urls returns one tagged default url");
like($$urls[0], qr/^sqlite:\/\/\/.*_TAP/,
  "with no test_pipeline_urls returns correct tagged default url");

$urls = get_test_urls(-driver => 'sqlite', -tag => 'TAP');
is(scalar(@$urls), 1, 
   "with no test_pipeline_urls returns one tagged url from an available driver");
like($$urls[0], qr/^sqlite:\/\/\/.*_TAP/,
  "with no test_pipeline_urls returns correct tagged url from an available driver");

# set EHIVE_TEST_PIPELINE_URLS

my %urls_by_tech_with_results = 
  ("mysql" => {"mysql://test1:secret@" . "anywhere.org:4321/" => 
	       "mysql://test1:secret@" . "anywhere.org:4321/" . whoami() . "_ehive_test",
	       "mysql://test2:whatever@" . "someplace.edu:4444/" =>
	       "mysql://test2:whatever@" . "someplace.edu:4444/" .  whoami() . "_ehive_test"},
   "pgsql" => {"pgsql://test3:abc123@" . "post.toastie:5555/" =>
	       "pgsql://test3:abc123@" . "post.toastie:5555/" . whoami() . "_ehive_test"},
   "sqlite" => {"sqlite:///" =>
		"sqlite:///" . whoami() . "_ehive_test"}
  );

local $ENV{EHIVE_TEST_PIPELINE_URLS} =
  join(" ", map {keys(%$_)} values(%urls_by_tech_with_results));

# no params
$urls = get_test_urls();
my @sorted_results_urls = sort {$a cmp $b} 
  map {values(%$_)} values(%urls_by_tech_with_results);
is(scalar(@$urls), scalar(@sorted_results_urls), 
   "defaults with defined test_pipeline_urls returns correct number of urls");
my @sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls, 
	  "defaults with defined test_pipeline_urls returns correct urls");

# just mysql
$urls = get_test_urls(-driver => 'mysql');
@sorted_results_urls = sort {$a cmp $b} values(%{$urls_by_tech_with_results{'mysql'}});
is(scalar(@$urls), scalar(@sorted_results_urls),
   "choosing driver with defined test_pipeline_urls returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls, 
	  "choosing driver with defined test_pipeline_urls returns correct urls");

# just mysql with a tag
$urls = get_test_urls(-driver => 'mysql', -tag => 'TAP');
@sorted_results_urls = sort {$a cmp $b}  map {$_ . "_TAP"} 
  values (%{$urls_by_tech_with_results{'mysql'}});
is(scalar(@$urls), scalar(@sorted_results_urls),
   "choosing driver+tag with defined test_pipeline_urls returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls, 
	  "choosing driver+tag with defined test_pipeline_urls returns correct urls");

# choosing multiple drivers (mysql and pgsql)
$urls = get_test_urls(-driver => 'mysql,pgsql');
@sorted_results_urls = sort {$a cmp $b} 
  map {values(%$_)} @urls_by_tech_with_results{qw(mysql pgsql)};
is(scalar(@$urls), scalar(@sorted_results_urls),
   "choosing multiple drivers with defined test_pipeline_urls returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls,
	  "choosing multiple drivers with defined test_pipeline_urls returns correct number of urls");

# choosing multiple drivers (mysql and pgsql) with a tag
$urls = get_test_urls(-driver => 'mysql,pgsql', -tag => 'TAP');
@sorted_results_urls = sort {$a cmp $b}
  map {$_ . "_TAP"} map {values(%$_)} @urls_by_tech_with_results{qw(mysql pgsql)};
is(scalar(@$urls), scalar(@sorted_results_urls),
   "choosing multiple drivers+tag with defined test_pipeline_urls returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls,
	  "choosing multiple drivers+tag with defined test_pipeline_urls returns correct number of urls");

# all drivers with a tag
$urls = get_test_urls(-tag => 'TAP');
@sorted_results_urls = sort {$a cmp $b}
  map {$_ . "_TAP"} map {values(%$_)} values(%urls_by_tech_with_results);
is(scalar(@$urls), scalar(@sorted_results_urls),
   "choosing tag with defined test_pipeline_urls returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls,
	  "choosing tag with defined test_pipeline_urls returns correct number of urls");

# unavailable driver
$urls = get_test_urls(-driver => 'dbaseII');
is(scalar(@$urls), 0,
   "choosing unavailable driver with defined test_pipeline_urls returns no urls");


# Give a specific database name in EHIVE_TEST_PIPELINE_URLS
%urls_by_tech_with_results = 
  ("mysql" => {"mysql://test1:secret@" . "anywhere.org:4321/" => 
	       "mysql://test1:secret@" . "anywhere.org:4321/" . whoami() . "_ehive_test",
	       "mysql://test2:customdb@" . "someplace.edu:4444/use_this_db" =>
	       "mysql://test2:customdb@" . "someplace.edu:4444/use_this_db"}
  );

local $ENV{EHIVE_TEST_PIPELINE_URLS} =
  join(" ", map {keys(%$_)} values(%urls_by_tech_with_results));

$urls = get_test_urls();
@sorted_results_urls = sort {$a cmp $b} 
  map {values(%$_)} values(%urls_by_tech_with_results);
is(scalar(@$urls), scalar(@sorted_results_urls), 
   "defaults with defined test_pipeline_urls with custom db returns correct number of urls");
@sorted_urls_returned = sort {$a cmp $b} @$urls;
is_deeply(\@sorted_urls_returned, \@sorted_results_urls, 
	  "defaults with defined test_pipeline_urls with custom db returns correct urls"); 

done_testing();
