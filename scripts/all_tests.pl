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

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use File::Basename;
use File::Find;
use File::Spec;
use Getopt::Long;
use TAP::Harness;

my $opts = {
  clean => 0,
  help => 0,
  skip => [],
  verbose => 0
};
my @args = ('clean|clear|c', 'help|h', 'verbose|v', 'list|tests|list-tests|l', 'skip=s@');

my $parse = GetOptions($opts, @args);
if(!$parse) {
  print STDERR "Could not parse the given arguments. Please consult the help\n";
  usage();
  exit 1;
} 

# If we were not given a directory as an argument, assume current directory
push(@ARGV, File::Spec->curdir()) if ! @ARGV;

# Print usage on '-h' command line option
if ($opts->{help}) {
  usage();
  exit;
}

# Get the tests
my $input_files_directories = [@ARGV];
my @tests = eval {
  get_all_tests($input_files_directories);
};
if($@) {
  printf(STDERR "Could not continue processing due to error: %s\n", $@);
  exit 1;
}

#Tests without cleans
my @no_clean_tests = sort grep { $_ !~ /CLEAN\.t$/ } @tests;

if (@{$opts->{skip}}) {
  my %skip = map { basename($_) => 1 } split(/,/, join(',', @{$opts->{skip}}));
  printf STDERR "Skipping tests: %s\n", join(', ', sort keys %skip);
  @no_clean_tests = grep { not $skip{basename($_)} } @no_clean_tests;
}

# List test files on '-l' command line option
if ($opts->{list}) {
  print "$_\n" for @no_clean_tests;
  exit;
}

# Make sure proper cleanup is done if the user interrupts the tests
$SIG{'HUP'} = $SIG{'KILL'} = $SIG{'INT'} = sub { 
  warn "\n\nINTERRUPT SIGNAL RECEIVED\n\n";
  clean();
  exit;
};

# Harness
my $harness = TAP::Harness->new({verbosity => $opts->{verbose}});

# Set environment variables
$ENV{'RUNTESTS_HARNESS'} = 1;

# Run all specified tests
my $results;
eval {
  $results = $harness->runtests(@no_clean_tests);
};

clean();

if($results->has_errors()) {
  my $count = $results->failed();
  $count   += $results->parse_errors();
  $count   += $results->exit();
  $count   += $results->wait();
  $count = 255 if $count > 255;
  exit $count;
}

sub usage {
    print <<EOT;
Usage:
\t$0 [-c] [-v] [<test files or directories> ...]
\t$0 -l        [<test files or directories> ...]
\t$0 -h

\t-l|--list|--tests|--list-tests\n\t\tlist available tests
\t-c|--clean|--clear\n\t\trun tests and clean up in each directory
\t\tvisited (default is not to clean up)
\t--skip <test_name>[,<test_name>...]\n\t\tskip listed tests
\t-v|--verbose\n\t\tbe verbose
\t-h|--help\n\t\tdisplay this help text

If no directory or test file is given on the command line, the script
will assume the current directory.
EOT
}

=head2 get_all_tests

  Description: Returns a list of testfiles in the directories specified by
               the @tests argument.  The relative path is given as well as
               with the testnames returned.  Only files ending with .t are
               returned.  Subdirectories are recursively entered and the test
               files returned within them are returned as well.
  Returntype : listref of strings.
  Exceptions : none
  Caller     : general

=cut

sub get_all_tests {
  my @files;
  my @out;

  #If we had files use them
  if ( $input_files_directories && @{$input_files_directories} ) {
    @files = @{$input_files_directories};
  }
  #Otherwise use current directory
  else {
    push(@files, File::Spec->curdir());
  }

  my $is_test = sub {
    my ($suspect_file) = @_;
    return 0 unless $suspect_file =~ /\.t$/;
    if(! -f $suspect_file) {
      warn "Cannot find file '$suspect_file'";
    }
    elsif(! -r $suspect_file) {
      warn "Cannot read file '$suspect_file'";
    }
    return 1;
  };

  while (my $file = shift @files) {
    #If it was a directory use it as a point to search from
    if(-d $file) {
      my $dir = $file;
      #find cd's to the dir in question so use relative for tests
      find(sub {
        if( $_ ne '.' && $_ ne '..' && $_ ne 'CVS') {
          if($is_test->($_)) {
            push(@out, $File::Find::name);
          }
        } 
      }, $dir);
    }
    #Otherwise add it if it was a test
    else {
      push(@out, $file) if $is_test->($file);
    }
  }

  return @out;
}

sub clean {
  # Unset environment variable indicating final cleanup should be
  # performed
  delete $ENV{'RUNTESTS_HARNESS'};
  if($opts->{clean}) {
    my @new_tests = get_all_tests();
    my @clean_tests = grep { $_ =~ /CLEAN\.t$/ } @new_tests;
    eval { $harness->runtests(@clean_tests); };
    warn $@ if $@;
  }
  return;
}
