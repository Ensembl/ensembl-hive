=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::EnsEMBL::Hive::Utils::Test;

use strict;
use warnings;
no warnings qw( redefine );

use Exporter;
use Carp qw{croak};
use File::Temp qw{tempfile};

use Data::Dumper;

use Test::More;
use Test::Exception;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');
use Bio::EnsEMBL::Hive::Utils::URL ('parse');

use Bio::EnsEMBL::Hive::Scripts::InitPipeline;
use Bio::EnsEMBL::Hive::Scripts::StandaloneJob;
use Bio::EnsEMBL::Hive::Scripts::RunWorker;


our @ISA         = qw(Exporter);
our @EXPORT      = ();
our %EXPORT_TAGS = ();
our @EXPORT_OK   = qw( standaloneJob init_pipeline runWorker get_test_urls get_test_url_or_die );

our $VERSION = '0.00';

sub _compare_job_warnings {
    my ($got, $expects) = @_;
    subtest "WARNING content as expected" => sub {
        plan tests => 2;
        my $exp_mess = shift @$expects;
        if (re::is_regexp($exp_mess)) {
            like(shift @$got, $exp_mess, 'WARNING message as expected');
        } else {
            is(shift @$got, $exp_mess, 'WARNING message as expected');
        }
        is_deeply($got, $expects, 'remaining WARNING arguments');
    };
}

sub _compare_job_dataflows {
    my ($got, $expects) = @_;
    is_deeply($got, $expects, 'DATAFLOW content as expected');
}

sub standaloneJob {
    my ($module_or_file, $param_hash, $expected_events, $flags) = @_;

    my $events_to_test = $expected_events ? [@$expected_events] : undef;

    my $input_id = stringify($param_hash);

    my $_test_event = sub {
        my ($triggered_type, @got) = @_;
        if (@$events_to_test) {
            my $expects = shift @$events_to_test;
            my $expected_type = shift @$expects;
            if ($triggered_type ne $expected_type) {
                fail("Got a $triggered_type event but was expecting $expected_type");
            } elsif ($triggered_type eq 'WARNING') {
                _compare_job_warnings(\@got, $expects);
            } else {
                _compare_job_dataflows(\@got, $expects);
            }
        } else {
            fail("event-stack is empty but the job emitted an event");
            print Dumper([@_]);
        }
    };

    local *Bio::EnsEMBL::Hive::Process::dataflow_output_id = sub {
        shift;
        &$_test_event('DATAFLOW', @_);
        return [1];
    } if $expected_events;

    local *Bio::EnsEMBL::Hive::Process::warning = sub {
        shift;
        &$_test_event('WARNING', @_);
    } if $expected_events;

    subtest "standalone run of $module_or_file" => sub {
        plan tests => 2 + ($expected_events ? 1+scalar(@$expected_events) : 0);
        lives_ok(sub {
            my $is_success = Bio::EnsEMBL::Hive::Scripts::StandaloneJob::standaloneJob($module_or_file, $input_id, $flags, undef, $flags->{language});
            if ($flags->{expect_failure}) {
                ok(!$is_success, 'job failed as expected');
            } else {
                ok($is_success, 'job completed');
            }
        }, sprintf('standaloneJob("%s", %s, (...), %s)', $module_or_file, stringify($param_hash), stringify($flags)));

        ok(!scalar(@$events_to_test), 'no untriggered events') if $expected_events;
    }
}


sub init_pipeline {
    my ($file_or_module, $options, $tweaks) = @_;

    $options ||= [];

    my $url;
    local @ARGV = @$options;

    lives_ok(sub {
        $url = Bio::EnsEMBL::Hive::Scripts::InitPipeline::init_pipeline($file_or_module, $tweaks);
        ok($url, 'pipeline initialized');
    }, sprintf('init_pipeline("%s", %s)', $file_or_module, stringify($options)));

    return $url;
}


sub runWorker {
    my ($pipeline, $specialization_options, $life_options, $execution_options) = @_;

    $specialization_options->{force_sync} = 1;

    lives_ok(sub {
        Bio::EnsEMBL::Hive::Scripts::RunWorker::runWorker($pipeline, $specialization_options, $life_options, $execution_options);
    }, sprintf('runWorker()'));
}

=head2 get_test_urls

  Arg [1]     : -driver => driver, -tag => tag
  Example     : my @urls = get_test_urls(-driver => 'mysql', -tag => 'longmult')
  Example     : my @urls = get_test_urls(-tag => 'gcpct')
  Example     : my @urls = get_test_urls(-driver => 'sqlite')
  Example     : my @urls = get_test_urls()
  Description : Creates a listref containing db urls based on the drivers specified in
              : the environment variable EHIVE_TEST_PIPELINE_URLS.
              : The URLs will be standard eHive URLs, looking like driver://connection/database
              : A database name consisting of [username]_ehive_test will be created
              : and placed in the URL
              : For example - mysql://me@127.0.0.1/ghopper_ehive_test
              :
              : If -tag is specified, then the list will have db names appended with '_tag' 
              : For example - (-tag => 'longmult') giving mysql://me@127.0.0.1/ghopper_ehive_test_longmult
              :
              : If -driver is specified, then the list will be restricted to urls for the
              : particular driver or comma-separated list of drivers specified (e.g. 'mysql,pgsql')
              :
              : If no drivers are specified in EHIVE_TEST_PIPELINE_URLS, it will check
              : to see if sqlite is available in the current path, and return a sqlite url
              : in the listref. Otherwise it will return an empty listref.
              :
 Returntype   : listref of db connection URLs as strings

=cut

sub get_test_urls {
  croak "wrong number of arguments for get_test_urls(); has to be even" if (scalar(@_) % 2);
  my %args = @_;
  my %argcheck = %args;
  delete(@argcheck{qw(-driver -tag)});
  croak "get_test_urls only accepts -driver and -tag as arguments" if (scalar(keys(%argcheck)) > 0);
 

  my %url_parses_by_driver;
  if (defined($ENV{EHIVE_TEST_PIPELINE_URLS})) {
    my @urls = split( /[\s,]+/, $ENV{EHIVE_TEST_PIPELINE_URLS} );
    foreach my $url (@urls) {
      if (my $parse = Bio::EnsEMBL::Hive::Utils::URL::parse($url) ) {
	push(@{$url_parses_by_driver{$parse->{driver}}}, $parse);
      } else {
	croak "badly formed url \"$url\" in EHIVE_TEST_PIPELINE_URLS";
      }
    }
  } else {
    my ($fh, $filename) = tempfile(UNLINK => 1);
    $url_parses_by_driver{'sqlite'} = [Bio::EnsEMBL::Hive::Utils::URL::parse('sqlite:///' . $filename)];
  }

  my $constructed_db_name = $ENV{USER} . "_ehive_test";

  my @driver_parses;
  if (defined($args{-driver})) {
    my @requested_drivers = split(/,/, $args{-driver});
    
    foreach my $requested_driver (@requested_drivers) {
      $requested_driver =~ s/^\s+|\s+$//g;  #trim whitespace
      if (defined($url_parses_by_driver{$requested_driver})) {
	push(@driver_parses, @{$url_parses_by_driver{$requested_driver}});
      }
    }
  } else {
    foreach my $parses_for_driver (values(%url_parses_by_driver)) {
      push (@driver_parses, @{$parses_for_driver});
    }
  }

  my @list_of_urls;
  foreach my $parsed_url (@driver_parses) {

    ## Use the default database name if needed, and append the tag (if given)
    $parsed_url->{'dbname'} ||= $constructed_db_name;
    $parsed_url->{'dbname'} .= '_'.$args{-tag} if defined $args{-tag};

    my $final_url = Bio::EnsEMBL::Hive::Utils::URL::hash_to_url($parsed_url);

    push (@list_of_urls, $final_url); 
  }

  return \@list_of_urls;
}


=head2 get_test_url_or_die

  Arg [1]     : see get_test_urls()
  Example     : my $url = get_test_url_or_die(-driver => 'mysql', -tag => 'longmult')
  Example     : my $url = get_test_url_or_die(-tag => 'gcpct')
  Example     : my $url = get_test_url_or_die(-driver => 'sqlite')
  Example     : my $url = get_test_url_or_die()
  Description : Wrapper around get_test_urls() that returns one of the test URLs, or
                die if no databases are available
  Returntype  : db connection URL as a string

=cut

sub get_test_url_or_die {
    my $list_of_urls = get_test_urls(@_);
    croak "No test databases are available" unless scalar(@$list_of_urls);
    return (sort @$list_of_urls)[0];
}

1;
