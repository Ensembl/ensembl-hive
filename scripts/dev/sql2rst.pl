#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
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

# 1st Feb 2011
# Generate an HTML documentation page from an SQL file.
#
# It needs to have a "javascript like" documentation above each table.
# See the content of the method sql_documentation_format();
####################################################################################


use strict;
#use warnings;  # commented out because this script is a repeat offender

use File::Basename ();
use File::Path qw(make_path);
use Getopt::Long;
use List::Util qw(max sum);

use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::Utils::GraphViz;


###############
### Options ###
###############

my ($sql_file,$fk_sql_file,$html_file,$db_team,$show_colour,$version,$header_flag,$sort_headers,$sort_tables,$intro_file,$embed_diagrams,$help,$help_format);
my ($url,$skip_conn,$db_connection);

usage() if (!scalar(@ARGV));
 
GetOptions(
    'i=s' => \$sql_file,
    'fk=s' => \$fk_sql_file,
    'o=s' => \$html_file,
    'd=s' => \$db_team,
    'c!'  => \$show_colour,
    'v=i' => \$version,
    'embed_diagrams!'  => \$embed_diagrams,
    'show_header!'     => \$header_flag,
    'sort_headers=i'   => \$sort_headers,
    'sort_tables=i'    => \$sort_tables,
    'url=s'            => \$url,
    'skip_connection'  => \$skip_conn,
    'intro=s'          => \$intro_file,
    'help!'            => \$help,
    'help_format'      => \$help_format,
);

usage() if ($help);
sql_documentation_format() if ($help_format);


if (!$sql_file) {
  print "> Error! Please give a sql file using the option '-i' \n";
  usage();
}

$show_colour    = 1 if (!defined($show_colour));
$header_flag    = 1 if (!defined($header_flag));
$sort_headers   = 1 if (!defined($sort_headers));
$sort_tables    = 1 if (!defined($sort_tables));

$skip_conn      = undef if ($skip_conn == 0);

# Dababase connection (optional)
if (defined($url) && !defined($skip_conn)) {
  $db_connection = new Bio::EnsEMBL::Hive::DBSQL::DBConnection(
    -url => $url,
  ) or die("DATABASE CONNECTION ERROR: Could not get a database adaptor for $url\n");
}




################
### Settings  ##
################

my $default_colour = '#000'; # Black

my $documentation = {};
my $tables_names = {'default' => []};
my @header_names = ('default');
my @colours = ($default_colour);
my %legend;

my $in_doc = 0;
my $in_table = 0;
my $header = 'default';
my $table = '';
my $info = '';
my $nb_by_col = 15;
my $count_sql_col = 0;
my $tag_content = '';
my $tag = '';
my $parenth_count = 0;
my $header_colour;
my $pk = [];

my $SQL_LIMIT = 50;


#############
## Parser  ##
#############

# Create a complex hash "%$documentation" to store all the documentation content

open my $sql_fh, '<', $sql_file or die "Can't open $sql_file : $!";
while (<$sql_fh>) {
  chomp $_;
  next if ($_ eq '');
  next if ($_ =~ /^\s*(DROP|PARTITION)/i);
  next if ($_ =~ /^\s*(#|--)/); # Escape characters
  
  # Verifications
  if ($_ =~ /^\/\*\*/)  { $in_doc=1; next; }  # start of a table documentation
  if ($_ =~ /^\s*create\s+table\s+(if\s+not\s+exists\s+)?`?(\w+)`?/i) { # start to parse the content of the table
    $pk = [];
    if ($table eq $2) { 
      $in_table=1;
      $parenth_count++;
    }
    else { 
      print STDERR "The documentation of the table $2 has not be found!\n";
    }
    next;
  }  
  next if ($in_doc==0 and $in_table==0);
  
  my $doc = remove_char($_);
  
  #================================================#
  # Parsing the documentation part of the SQL file #
  #================================================#
  if ($in_doc==1) {
    # Header name
    if ($doc =~ /^\@header\s*(.+)$/i and $header_flag == 1) {
      $header = $1;
      unless (exists $tables_names->{$header}) {
        push (@header_names,$header);
        $tables_names->{$header} = [];
      }
      next;
    }    
    # Table name
    elsif ($doc =~ /^\@table\s*(\w+)/i) {
      $table = $1;
      push(@{$tables_names->{$header}},$table);
      $documentation->{$header}{'tables'}{$table} = { 'desc' => '', 'colour' => '', 'column' => [], 'example' => [], 'see' => [], 'info' => [] };
      $tag = $tag_content = '';    
    }
    # Description (used for both set, table and info tags)
    elsif ($doc =~ /^\@(desc)\s*(.+)$/i) {
      fill_documentation ($1,$2);
    }
    # Colour of the table header (used for both set, table) (optional)
    elsif ($doc =~ /^\@(colour)\s*(.+)$/i) {
      fill_documentation ($1,$2) if ($show_colour);
    }
    # Column
    elsif ($doc =~ /^\@(column)\s*(.+)$/i) {
      fill_documentation ($1,$2);
    }
    # Example 
    elsif ($doc =~ /^\@(example)\s*(.+)$/i) {
      fill_documentation ($1,$2);
    }
    # See other tables
    elsif ($doc =~ /^\@(see)\s*(\w+)\s*$/i) {
      fill_documentation ($1,$2);  
    }
    # Addtional information block
    elsif ($doc =~ /^\@(info)\s*(.+)$/i) {
      fill_documentation ();
      $info = $2;
      next;
    }
    # End of documentation
    elsif ($doc =~ /^\*\//) { # End of the documentation block
      fill_documentation (); # Add the last tag content to the documentation hash
      $in_doc=0;
      next; 
    }
    # Add legend colour description
    elsif ($doc =~ /^\@(legend)\s*(#\S+)\s+(.+)$/i) {
      $legend{$2} = $3;
    }
    elsif ($doc =~ /^\s*(.+)$/) { # If a tag content is split in several lines
      $tag_content .= " $1";
    }
  }
  
  #=====================================================#
  # Parsing of the SQL table to fetch the columns types #
  #=====================================================#
  elsif ($in_table==1) {
    
    # END OF TABLE DEFINITION
    # Can't do this easily with a simply regex as there are varying valid formats
    # The end of the table definition is actually defined by 2nd enclosing bracket
    
    # Regex counting VOODOO!
    # This basically puts the regex in a list context
    # before inc/dec'ing with it in a scalar context.
    $parenth_count +=()= $doc =~ /\(/gi;
    $parenth_count -=()= $doc =~ /\)/gi;


    if ($parenth_count == 0) { # End of the sql table definition
    if (scalar(@$pk)) {
      add_column_index('primary key', join(',', @$pk));
    }
    if (scalar @{$documentation->{$header}{'tables'}{$table}{column}} > $count_sql_col) {
      print STDERR "Description of a non existant column in the table $table!\n";
    }

    $in_table=0;
    $count_sql_col = 0;
    $table='';
    $parenth_count = 0;
    }
    else {

      #---------#
      # INDEXES #
      #---------#
      
      # Remove the comments
      $doc =~ s/--\s.*$//;

      # Skip the blank lines
      next if ($doc =~ /^\s+$/);

      if ($doc =~ /FOREIGN\s+KEY\s+\((\S+)\)\s+REFERENCES\s+(\S+)\s*\((\S+)\)/i) { # foreign key
        push @{$documentation->{$header}{'tables'}{$table}->{foreign_keys}}, [$1,$2,$3];
        next;
      }
      elsif ($doc =~ /^\s*(primary\s+key)\s*\w*\s*\((.+)\)/i or $doc =~ /^\s*(unique)\s*\((.+)\)/i){ # Primary or unique;
        add_column_index($1,$2);
        next;
      }
      elsif ($doc =~ /^\s*(unique\s+)?(key|index)\s+([^\s\(]+)\s*\((.+)\)/i) { # Keys and indexes
        add_column_index("$1$2",$4,$3);
        next;
      }
      elsif ($doc =~ /^\s*(unique)\s+(\S*)\s*\((.+)\)/i) { # Unique
        add_column_index("$1",$3,$2);
        next;
      }
      elsif ($doc =~ /^\s*(key|index)\s+\((.+)\)/i) { # Keys
        add_column_index("$1",$2);
        next;
      }
      
      #----------------------------------#
      # COLUMNS & TYPES & DEFAULT VALUES #
      #----------------------------------#
      my $col_name = '';
      my $col_type = '';
      my $col_def  = '';
      
      # All the type is contained in the same line (type followed by parenthesis)
      if ($doc =~ /^\W*(\w+)\W+(\w+\s?\(.*\))/ ){
        $col_name = $1;
        $col_type = $2;
        if ($doc =~ /default\s+([^,\s]+)\s*.*(,|#).*/i) { $col_def = $1; } # Default value
      }
    
      # The type is written in several lines
      elsif ($doc =~ /^\W*(\w+)\W+(enum|set)(\s?\(.*)/i){ # The content is split in several lines
        $col_name= $1;
        $col_type="$2$3<br />";
        my $end_type = 0;
        while ($end_type != 1){
          my $line = <$sql_fh>;
          chomp $line;
          $line = remove_char($line);

          # Regex counting VOODOO again
          $parenth_count +=()= $line =~ /\(/gi;
          $parenth_count -=()= $line =~ /\)/gi;
        
          if ($line =~ /\)/) { # Close parenthesis
            $end_type=1; 
            $line =~ /^\s*(.+)\)/;
            $col_type .= "$1)"; 
          }
          else { # Add the content of the line
            $line =~ /^\s*(.+)/;
            $col_type .= $1.'<br />';
          }
          if ($line =~ /default\s+([^,\s]+)\s*.*(,|#).*/i) { $col_def = $1; } # Default value
        }
      }
    
      # All the type is contained in the same line (type without parenthesis)
      elsif ($doc =~ /^\s*\W*(\w+)\W+(\w+)/ ){
        $col_name = $1;
        $col_type = $2;
        if ($doc =~ /default\s*([^,\s]+)\s*.*(,|#).*/i) { $col_def = $1; } # Default value
      }

      # Default value
      if (!defined($col_def) || $col_def eq '') {
        $col_def = ($doc =~ /not\s+null/i ) ? '*not set*' : 'NULL';
      }

      add_column_type_and_default_value($col_name,$col_type,$col_def);

      if ($doc =~ /\bprimary\s+key\b/i) {
        push @$pk, $col_name;
      }
    }
  }
}
close($sql_fh);

my %table_documentation;
foreach my $c (keys %$documentation) {
  my $h = $documentation->{$c};
  foreach my $table_name (keys %{$h->{tables}}) {
    $table_documentation{$table_name} = $h->{tables}->{$table_name};
    $h->{tables}->{$table_name}->{category} = $c;
  }
}

if ($fk_sql_file) {
    open $sql_fh, '<', $fk_sql_file or die "Can't open $fk_sql_file : $!";
    while (<$sql_fh>) {
      chomp $_;
      next if ($_ eq '');
      my $doc = remove_char($_);
      if ($doc =~ /ALTER\s+TABLE\s+(\S+)\s+ADD.*FOREIGN\s+KEY\s+\((\S+)\)\s+REFERENCES\s+(\S+)\((\S+)\)/i) {
          push @{$table_documentation{$1}->{foreign_keys}}, [$2,$3,$4];
      } elsif ($doc =~ /ALTER.*FOREIGN/i) {
          die "Unrecognized: $doc";
      }
    }
    close($sql_fh);
}

sub table_box {
    my ($graph, $table_name) = @_;
    my $table_doc = $table_documentation{$table_name};
    my @rows = map {sprintf('<tr><td bgcolor="white" port="port%s">%s%s</td></tr>', $_->{name}, ($_->{index} =~ /\bprimary\b/i ? '<B>PK</B>&nbsp;&nbsp;' : ''), $_->{name})} @{$table_doc->{column}};
    $graph->add_node($table_name,
        'shape' => 'box',
        'style' => 'filled,rounded',
        'fillcolor' => $table_doc->{colour},
        'label' => sprintf('<<table border="0"><th><td><font point-size="16">%s</font></td></th><hr/>%s</table>>', $table_name, join('', @rows)),
    );
}

sub generate_whole_diagram {
    my ($show_clusters, $column_links) = @_;
    my $graph = Bio::EnsEMBL::Hive::Utils::GraphViz->new(
        'label' => "$db_team schema diagram",
        'fontsize' => 20,
        $column_links
          ? ( 'rankdir' => 'LR', 'concentrate' => 'true', )
          : ( 'splines' => 'ortho', ),
    );
    foreach my $table_name (sort keys %table_documentation) {
        table_box($graph, $table_name);
    }
    foreach my $table_name (sort keys %table_documentation) {
        foreach my $fk (@{$table_documentation{$table_name}->{foreign_keys}}) {
            $graph->add_edge($table_name => $fk->[1],
                'style' => 'dashed',
                $column_links ? (
                    'from_port' => "$fk->[0]:e",
                    'to_port' => "$fk->[2]:w",
                ) : (),
            );
        }
    }

    if ($show_clusters) {
        foreach my $h (sort keys %$documentation) {
            my $cluster_id = clean_name($h);
            my $c = blend_colors($documentation->{$h}->{colour}, '#FFFFFF', 0.8);
            $graph->cluster_2_attributes()->{$cluster_id} = {
                'cluster_label' => $h,
                'style' => 'rounded,filled,noborder',
                'fill_colour_pair' => ["#$c"],
            };
            my @cluster_nodes;
            $graph->cluster_2_nodes()->{$cluster_id} = \@cluster_nodes;
            foreach my $t (sort keys %{$documentation->{$h}->{tables}}) {
                push @cluster_nodes, $t;
            }
        }
    }
    return $graph;
}


sub blend_colors {
    my ($color1, $color2, $alpha) = @_;
    my @rgb1 = map {hex($_)} unpack("(A2)*", substr $color1, 1);
    my @rgb2 = map {hex($_)} unpack("(A2)*", substr $color2, 1);
    my @rgb = map {int($rgb1[$_] + $alpha * ($rgb2[$_]-$rgb1[$_]))}  0..2;
    my $c = join('', map {sprintf('%X', $_)} @rgb);
    return $c;
}

sub sub_table_box {
    my ($graph, $table_name, $fields) = @_;
    my $table_doc = $table_documentation{$table_name};
    my @rows;
    my $has_ellipsis;
    foreach my $c (@{$table_doc->{column}}) {
        if ($fields->{$c->{name}}) {
            push @rows, sprintf('<tr><td bgcolor="white" port="port%s">%s%s</td></tr>', $c->{name}, ($c->{index} =~ /\bprimary\b/i ? '<B>PK</B>&nbsp;&nbsp;' : ''), $c->{name});
            $has_ellipsis = 0;
        } elsif (!$has_ellipsis) {
            push @rows, '<tr><td bgcolor="white"><i>...</i></td></tr>';
            $has_ellipsis = 1;
        }
    }
    $graph->add_node($table_name,
        'shape' => 'box',
        'style' => 'filled,rounded',
        'fillcolor' => $table_doc->{colour},
        'label' => sprintf('<<table border="0"><th><td><font point-size="16">%s</font></td></th><hr/>%s</table>>', $table_name, join('', @rows)),
    );
}

sub generate_sub_diagram {
    my ($cluster, $column_links) = @_;
    my $graph = Bio::EnsEMBL::Hive::Utils::GraphViz->new(
        'label' => "$db_team schema diagram: $cluster tables",
        'fontsize' => 20,
        $column_links
          ? ( 'rankdir' => 'LR', 'concentrate' => 'true', )
          : ( 'splines' => 'ortho', ),
    );
    foreach my $table_name (sort keys %{$documentation->{$cluster}->{tables}}) {
        table_box($graph, $table_name);
    }
    my %clusters_to_draw = ($cluster => 1);
    my %other_table_fields;
    my @drawn_fks;
    foreach my $table_name (sort keys %table_documentation) {
        foreach my $fk (@{$table_documentation{$table_name}->{foreign_keys}}) {
            if ($table_documentation{$table_name}->{category} eq $cluster) {
                $other_table_fields{$fk->[1]}->{$fk->[2]} = 1;
                $clusters_to_draw{ $table_documentation{$fk->[1]}->{category} } = 1;
                push @drawn_fks, [$table_name, @$fk];
            } elsif ($table_documentation{$fk->[1]}->{category} eq $cluster) {
                $other_table_fields{$table_name}->{$fk->[0]} = 1;
                $clusters_to_draw{ $table_documentation{$table_name}->{category} } = 1;
                push @drawn_fks, [$table_name, @$fk];
            }
        }
    }
    foreach my $table_name (sort keys %other_table_fields) {
        sub_table_box($graph, $table_name, $other_table_fields{$table_name} || {}) if $cluster ne $table_documentation{$table_name}->{category};
    }
    foreach my $fk (@drawn_fks) {
        my $table_name = shift @$fk;
        $graph->add_edge($table_name => $fk->[1],
            'style' => 'dashed',
            $column_links ? (
                'from_port' => $fk->[0].':e',
                'to_port' => $fk->[2].':w',
            ) : (),
        );
    }

    foreach my $h (sort keys %clusters_to_draw) {
        #next unless $h eq $cluster;
        my $cluster_id = clean_name($h);
        my $c = blend_colors($documentation->{$h}->{colour}, '#FFFFFF', 0.8);
        $graph->cluster_2_attributes()->{$cluster_id} = {
            'cluster_label' => $h,
            ($h eq $cluster) ?
                ( 'style' => 'rounded,filled,noborder', 'fill_colour_pair' => ["#$c"], )
              : ( 'style' => 'filled,noborder', 'fill_colour_pair' => ['white'] ),
        };
        my @cluster_nodes;
        $graph->cluster_2_nodes()->{$cluster_id} = \@cluster_nodes;
        foreach my $t (sort keys %{$documentation->{$h}->{tables}}) {
            push @cluster_nodes, $t if (($h eq $cluster) || $other_table_fields{$t});
        }
    }
    return $graph;
}

sub clean_name {
    my $n = shift;
    $n =~ s/\s+/_/g;
    $n =~ s/[\-\/]+/_/g;
    return lc $n;
}

# Sort the headers names by alphabetic order
if ($sort_headers == 1) {
  @header_names = sort(@header_names);
}
# Sort the tables names by alphabetic order
if ($sort_tables == 1) {
  while ( my($header_name,$tables) = each (%{$tables_names})) {
    @{$tables} = sort(@{$tables});
  }
}

# Remove the empty headers (e.g. "default")
@header_names = grep {scalar(@{$tables_names->{$_}})} @header_names;


#####################
## Schema diagrams ##
#####################
my %diagram_dotcode;
if ($embed_diagrams) {
    my $graph = generate_whole_diagram('show_clusters', 'column_links');
    $diagram_dotcode{''} = $graph->as_debug();
    foreach my $c (@header_names) {
        my $graph = generate_sub_diagram($c, 'column_links');
        $diagram_dotcode{$c} = $graph->as_debug();
    }
}


#################
## RST content ##
#################

my $html_content = '';

# Legend link
if ($show_colour and scalar @colours > 1 and $header_flag != 1) {
  $html_content .= qq{A colour legend is available at the <a href="#legend">bottom of the page</a>.\n<br /><br />};
}

#=============================================#
# List of tables by header (i.e. like a menu) #
#=============================================#
$html_content .= display_tables_list();
my $table_count = 1;
my $col_count = 1;

$html_content .= ".. raw:: latex\n\n   \\begin{landscape}\n\n";

#========================================#
# Display the detailled tables by header #
#========================================#
my $header_id = 1;
foreach my $header_name (@header_names) {
  my $tables = $tables_names->{$header_name};
   
  #----------------#  
  # Header display #
  #----------------#  
    my $category_title = $documentation->{$header_name}->{'colour'} ? sprintf(':schema_table_header:`<%s,square>%s`', $documentation->{$header_name}->{'colour'}, $header_name) : $header_name;
    $html_content .= rst_title($category_title, '~') . "\n";
  
  #------------------------#
  # Additional information #
  #------------------------#
    $html_content .= rst_add_indent_to_block($documentation->{$header_name}{'desc'}, "    ") . "\n\n" if $documentation->{$header_name}{'desc'};
    if ($embed_diagrams) {
        my $l = clean_name($header_name);
        $html_content .= ".. schema_diagram::\n\n" . rst_add_indent_to_block($diagram_dotcode{$header_name}, '   ') . "\n\n";
    }
  
  #----------------#
  # Tables display #
  #----------------#
  foreach my $t_name (@{$tables}) {
    my $data = $documentation->{$header_name}{'tables'}{$t_name};
    
    my $table_title = $documentation->{$header_name}->{'colour'} ? sprintf(':schema_table_header:`<%s,round>%s`', $documentation->{$header_name}->{'colour'}, $t_name) : $t_name;
    $html_content .= rst_title($table_title, '+');
    $html_content .= add_description($data) . "\n";
    $html_content .= add_columns($t_name,$data);
    $html_content .= add_examples($t_name,$data);
  }
}


$html_content .= ".. raw:: latex\n\n   \\end{landscape}\n\n";


######################
## HTML/output file ##
######################
my $output_fh;
if ($html_file) {
    open $output_fh, '>', $html_file or die "Can't open $html_file : $!";
} else {
    $output_fh = \*STDOUT;
}
print $output_fh slurp_intro($intro_file)."\n";
print $output_fh $html_content."\n";
close($output_fh);


sub rst_title {
    my ($title, $underscore_symbol) = @_;
    return $title . "\n" . ($underscore_symbol x length($title)) . "\n";
}

sub block_width {
    my ($block) = @_;
    my @lines = split /\n/, $block;
    return max(map {length($_)} @lines);
}

sub column_width {
    my ($data, $i) = @_;
    return max(map {block_width($_->[$i])} @$data);
}

sub rst_list_table {
    my ($data, $class) = @_;

    my @widths = map {column_width($data, $_)} 0..(scalar(@{$data->[0]})-1);
    my $w = ":widths: ".join(" ", @widths);

    my $table_content = join("\n", map {rst_list_table_row($_)} @$data);
    return ".. list-table::\n" . rst_add_indent_to_block(":header-rows: 1\n$w\n" . ($class ? ":class: $class\n" : "") . "\n" . $table_content, "   ") . "\n\n";
}

sub rst_list_table_row {
    my ($row) = @_;
    my $first_cell = shift @$row;
    return rst_add_indent_to_block($first_cell, "    ", "* - ") . "\n" . join("\n", map {rst_add_indent_to_block($_, "    ", "  - ")} @$row);
}

sub rst_add_indent_to_block {
    my ($block, $indent, $first_indent) = @_;
    $first_indent //= $indent;
    my @lines = split /\n/, $block;
    my $first_line = shift @lines;
    if (@lines) {
        return $first_indent . $first_line . "\n" . join("\n", map {$indent . $_} @lines);
    }
    return $first_indent . $first_line;
}

sub rst_bullet_list {
    my ($data, $list_symbol) = @_;
    $list_symbol //= '-';
    return join("\n", map {$list_symbol . " " . $_} @$data);
}

###############
##  Methods  ##
###############

# List the table names.  Group them if possible
# By default there is one group, named "default" and it contains all the tables.
sub display_tables_list {

  
    my $rest = '';

    if ($embed_diagrams) {
        $rest .= rst_title('Schema diagram', '=') . "\n";
        $rest .= "The $db_team schema diagrams are automatically generated as PNG images with Graphviz, and show the links between columns of each table.\n";
        $rest .= "Here follows the overall schema diagram, while the individual diagrams of each category are available below, together with the table descriptions.\n\n";
        $rest .= ".. schema_diagram::\n\n" . rst_add_indent_to_block($diagram_dotcode{''}, '   ') . "\n\n";
    }

    $rest .= rst_title('Table list', '=') . "\n";
    $rest .= "Here is the list of all the tables found in a typical $db_team database, grouped by categories.\n\n";
  
    if (scalar(@header_names) == 1) {
        return rst_bullet_list($tables_names->{$header_names[0]}) . "\n";
    }

    # Remove the empty headers (e.g. "default")
    my @useful_header_names = grep {scalar(@{$tables_names->{$_}})} @header_names;

    # No more than 3 categories at a time
    my $max_headers_per_line = 3;
    while (scalar(@useful_header_names)) {
        my @headers_this_time = splice(@useful_header_names, 0, $max_headers_per_line);

        my @first_row = map {$documentation->{$_}->{'colour'} ? sprintf(':schema_table_header:`<%s,square>%s`', $documentation->{$_}->{'colour'}, $_) : $_} @headers_this_time;
        my @second_row = map {rst_bullet_list([map {$_.'_'} @{$tables_names->{$_}}])} @headers_this_time;
        my @data = (\@first_row, \@second_row);

        $rest .= rst_list_table(\@data, 'sql-schema-table');
    }
  
    return $rest;
}



# Method to pick up the documentation information contained in the SQL file.
# If the line starts by a @<tag>, the previous tag content is added to the documentation hash.
# This method allows to describe the content of a tag in several lines.
sub fill_documentation {
  my $t1 = shift;
  my $t2 = shift;
  
  if ($tag ne '') {
    # Description tag (info, table or header)
    if ($tag eq 'desc') {
      # Additional description
      if ($info ne '') {
        $tag_content = $info.'@info@'.$tag_content;
        # Table: additional information        
        if ($table ne '') {
          push(@{$documentation->{$header}{'tables'}{$table}{'info'}},$tag_content);
        }
        # Header: additional information
        else {
          if (!$documentation->{$header}{'info'}) {
            $documentation->{$header}{'info'} = [];
          }
          push(@{$documentation->{$header}{'info'}},$tag_content);
        }
        $info = '';
      }
      # Header description
      elsif(!$documentation->{$header}{'tables'}) {
        $documentation->{$header}{'desc'} = $tag_content;
      }
      # Table description
      else {
        $documentation->{$header}{'tables'}{$table}{$tag} = $tag_content;
      }
    }
    elsif ($tag eq 'colour') {
      if(!$documentation->{$header}{'tables'}) {
        $documentation->{$header}{'colour'} = $tag_content;
        $header_colour = 1;
      }
      elsif ($table ne '') {
        $documentation->{$header}{'tables'}{$table}{$tag} = $tag_content;
        if (! grep {$tag_content eq $_} @colours) {
          push (@colours,$tag_content);
        }
      }
    }
    elsif ($tag eq 'column') {
      $tag_content =~ /(\w+)[\s\t]+(.*)/;
      
      my $column = { 'name'    => $1,
                     'type'    => '',
                     'default' => '',
                     'index'   => '',
                     'desc'    => $2
                   };
      if ($2 eq '') {
        print STDERR "COLUMN: The description content of the column '$1' is missing in the table $table!\n";
      }
      push(@{$documentation->{$header}{'tables'}{$table}{$tag}},$column);
    } 
    else{
      push(@{$documentation->{$header}{'tables'}{$table}{$tag}},$tag_content);
    }
  }
  # New tag initialised
  if ($t1) {
    $tag = $t1;
    $tag_content = $t2;
  }
  else {
    $tag = $tag_content = '';  
  }
}
 

# Method generating the HTML code to display the description content
sub add_description {
  my $data = shift;
  
  # Search if there are some @link tags in the description text.
  my $desc = add_internal_link($data->{desc},$data);
  
  return $desc . "\n";
}


# Method generating the HTML code of the table listing the columns of the given SQL table.
sub add_columns {
  my $table = shift;
  my $data  = shift;
  my $cols  = $data->{column};
  
  my @data;
  my @header_row = ('Column', 'Type', 'Default value', 'Description', 'Index');
  push @data, \@header_row;
  
  foreach my $col (@$cols) {
    my $name    = $col->{name};
    my $type    = $col->{type};
    my $default = $col->{default};
    my $desc    = $col->{desc};
    my $index   = $col->{index};
    
    # links
    $desc = add_internal_link($desc,$data);
    
    $type = parse_column_type($type);
    
    my @row = ("**$name**", $type, $default, $desc, $index);
    push @data, \@row;
  }
  
  return rst_list_table(\@data);
}


# Method generating the HTML code to display the content of the tags @example (description + SQL query + Table of SQL query results)
sub add_examples {
  my $table = shift;
  my $data  = shift;
  my $examples  = $data->{example};
  my $html;

  my $nb = (scalar(@$examples) > 1) ? 1 : '';

  foreach my $ex (@$examples) {
    my @lines = split("\n",$ex);
    my $nb_display = ($nb ne '') ? " $nb" : $nb;
    $html .= rst_title("Example$nb_display:", '-') . "\n";
    my $has_desc = 0;
    my $sql;
    
    # Parse the example lines
    foreach my $line (@lines) {
      chomp($line);
      
      # Pick up the SQL query if it exists
      if ($line =~ /(.*)\s*\@sql\s*(.+)/) {
        $html .= $1;
        $sql = $2;
      } elsif (!defined($sql)){
        $html .= $line;
        $has_desc = 1;
      }
      else {
        $sql .= $line;
      }
    }
    $html .= "\n\n";
    
    # Search if there are some @link tags in the example description.
    $html = add_internal_link($html,$data);
    
    # Add a table of examples
    if (defined($sql)) {
      my $sql_table = '';
      if (!defined($skip_conn) && defined($url)) {
        $sql_table = get_example_table($sql,$table,$nb);
      }
             
      $html .= ".. code-block:: sql\n\n" . rst_add_indent_to_block($sql, "   ") . "\n\n" . $sql_table . "\n";
    }
    $nb ++;
  }
  
  return $html;
}


# Method generating the HTML code to display the content of the tags @see
sub add_see {
  my $sees = shift;
  my $html = '';

  if (scalar @$sees) {
    $html .= qq{    <td class="sql_schema_extra_left">\    <p style="font-weight:bold">See also:</p>\n  <ul>\n};
    foreach my $see (@$sees) {
      $html .= qq{      <li><a href="#$see">$see</a></li>\n};
    }
    $html .= qq{      </ul>\n    </td>\n};
  }

  return $html;
}


# Method searching the tag @link into the string given as argument and replace it by an internal HTML link 
sub add_internal_link {
  my $desc = shift;
  my $data = shift;
  while ($desc =~ /\@link\s?(\w+)/) {
    my $link = $1;
    if ((!grep {$link eq $_} @{$data->{see}}) and defined($link)) {
      push @{$data->{see}}, $link;
    }
    my $table_to_link = $link;
    $desc =~ s/\@link\s?\w+/$table_to_link/;
  }
  return $desc;
}


# Method parsing the index information from the SQL table description in order to display it in the
# HTML table listing the columns of the corresponding SQL table.
sub add_column_index {
  my $idx_type = shift;
  my $idx_col  = shift;
  my $idx_name = shift;
  
  my $index = $idx_type;
  if (!defined($idx_name)) {
    $idx_name = $idx_col;
  }
  if ($idx_type !~ /primary/i) {
    $index .= ": *$idx_name*";
  }
  my @idx_cols = split(',',$idx_col); # The index can involve several columns
  
  my %is_found = ();
  foreach my $i_col (@idx_cols) {
    $i_col =~ s/\s//g; # Remove white spaces
    # In case of index using a number characters for a column
    if ($i_col =~ /(.+)\(\d+\)/) {
      $i_col = $1;
    } 
    $is_found{$i_col} = 0;
    foreach my $col (@{$documentation->{$header}{tables}{$table}{column}}) {
      if ($col->{name} eq $i_col) {
        if ($col->{index} ne '') {
          $col->{index} .= "\n";
        }
        $col->{index} .= lc($index);
        $is_found{$i_col} = 1;
        last;
      }
    }
  }
  # Description missing
  while (my ($k,$v) = each(%is_found)) {
    if ($v==0) {
      print STDERR "INDEX: The description of the column '$k' is missing in the table $table!\n";
    }
  }
}


# Method parsing the column type and default value from the SQL table description, in order to display them in the
# HTML table listing the columns of the corresponding SQL table.
sub add_column_type_and_default_value {
  my $c_name    = shift;
  my $c_type    = shift;
  my $c_default = shift;
  $count_sql_col ++;
  
  my $is_found = 0;
  foreach my $col (@{$documentation->{$header}{'tables'}{$table}{column}}) {
    if ($col->{name} eq $c_name) {
      $col->{type} = $c_type;
      $col->{default} = $c_default if ($c_default ne '');
      $is_found = 1;
      last;
    }
  }
  # Description missing
  if ($is_found==0) {
    print STDERR "COLUMN: The description of the column '$c_name' is missing in the table $table!\n";
  }
}


# Display the types "enum" and "set" as an HTML list (<ul><li>)
sub parse_column_type {
  my $type = shift;
  $type =~ /^\s*(enum|set)\s*\((.*)\)/i;
  my $c_type = uc($1);
  my $c_data = $2;
  return $type unless ($c_data);
  
  $c_data =~ s/'//g;
  $c_data =~ s/"//g;
  $c_data =~ s/\s//g;
  $c_data =~ s/<br \/>//g;
  
  my @items_list = split(',',$c_data);
  
  return $type unless (scalar(@items_list) > 1);
  
  return $c_type . ":\n\n" . rst_bullet_list(\@items_list);
}


# Method to query the database with the SQL query example, get the result and display it
# in an HTML table.
sub get_example_table {
  my $sql   = shift;
  my $table = shift;
  my $nb    = shift;
  my $html;
  
  $sql =~ /select\s+(.+)\s+from/i;
  my $cols = $1;
  $cols = '*' if $cols =~ /^\*\s/;
  my @tcols;
     
  foreach my $col (split(',',$cols)) {
  
    # Columns selection like the expressions "table.*" or "*"
    my $table_name;
    $table_name = $table if ($cols eq '*');
    $table_name = $1 if ($col =~ /(\S+)\.\*/ and !defined($table_name));
    if (defined($table_name)) {
      my $table_cols = $db_connection->selectall_arrayref(qq{SHOW COLUMNS FROM $table_name});
      foreach my $col (@$table_cols) {
        push(@tcols,$col->[0]);
      }
      next;
    }
     
    # Check for alias
    $col = $1 if ($col =~ /\s+as\s+(\S+)$/i);
       
    $col =~ s/ //g;
    push(@tcols,$col);
  }
  
  my $results = $db_connection->selectall_arrayref($sql);
  if (scalar(@$results)) {
    my @data;
    push @data, \@tcols;
    
    my $count = 0;
    foreach my $result (@$results) {
      last if ($count >= $SQL_LIMIT);
      push @data, [map {$_ // 'NULL'} @$result];
      $count ++;
    }
    return rst_list_table(\@data);
  } else {
    my $msg = qq{The SQL query displayed above returned no results!};
    print STDERR qq{SQL: $sql\n$msg\n};
    return ".. error::\n\n   $msg\n\n";
  }
}



# Removed the character(s) ` from the read line.
sub remove_char {
  my $text = shift;
  $text =~ s/`//g;
  return $text;
}


# Insert the introduction text of the web page
sub slurp_intro {
  my $intro_file = shift;
  return qq{This document describes the tables that make up the $db_team schema. Tables are grouped into categories, and the purpose of each table is explained.\n} if (!defined $intro_file);

  local $/=undef;
  open my $fh, '<', $intro_file or die "Can't open $intro_file: $!";
  my $intro_html = <$fh>;
  close $fh;
  
  $intro_html =~ s/####DB_VERSION####/$version/g if (defined($version));
  
  return $intro_html;
}


##################
## Help methods ##
##################

sub sql_documentation_format {
  print q{
  
#--------------------------#
# Example of documentation #  
#--------------------------#
  
/**
@table variation

@desc This is the schema's generic representation of a variation.

@colour #FF0000

@column variation_id       Primary key, internal identifier.
@column source_id          Foreign key references to the \@link source table.
@column name               Name of the variation. e.g. "rs1333049".
@column validation_status  Variant discovery method and validation from dbSNP.
@column ancestral_allele   Taken from dbSNP to show ancestral allele for the variation.
@column flipped            This is set to 1 if the variant is flipped.
@column class_so_id        Class of the variation, based on the Sequence Ontology.

@example Example of SQL query for to retrieve data from this table:
         @sql SELECT * FROM variation WHERE source_id=1 LIMIT 10;

@see variation_synonym
@see flanking_sequence
@see failed_variation
@see variation_feature
@see variation_group_variation
@see allele
@see allele_group_allele
@see individual_genotype_multiple_bp
*/


create table variation (
    variation_id int(10) unsigned not null auto_increment, # PK
    source_id int(10) unsigned not null, 
    name varchar(255),
    validation_status SET('cluster','freq','submitter','doublehit','hapmap','1000Genome','failed','precious'),
    ancestral_allele text,
    flipped tinyint(1) unsigned NULL DEFAULT NULL,
    class_so_id ENUM('SO:0001483','SO:1000002','SO:0000667') DEFAULT 'SO:0001059', # default to sequence_alteration

    primary key( variation_id ),
    unique ( name ),
    key source_idx (source_id)
);

/**
@legend #FF0000 Table storing variation data
*/


#========================================================================================================================#


#------------------#
# Tags description #
#------------------#

 /** and */ : begin and end of the document block
 @header    : tag to create a group of tables
 @table     : name of the sql table
 @desc      : description of the role/content of the table, set or info tags
 @colour    : tag to colour the header of the table (e.g. if the tables are coloured in the graphic SQL schema and you want to reproduce it in the HTML version)
 @column    : column_name [tab(s)] Column description. Note: 1 ligne = 1 column
 @see       : tables names linked to the described table
 @link      : Internal link to an other table description. The format is ... @link table_name ...
 @info      : tag to describe additional information about a table or a set of tables
 @legend    : tag to fill the colour legend table at the end of the HTML page
 @example   : tag to add some examples, like examples of SQL queries
 @sql       : tag inside the @example tag, used to delimit a SQL query

};
  exit(0);
}


sub usage {
  
  print q{
  Usage: perl sql2html.pl [OPTION]
  
  Convert the SQL documentation into an HTML document.
  
  Options:

    -help            Print this message
    -help_format     Print the description of the documentation format in the SQL files
      
    An input file must be specified. This file must be a SQL file, with the "Java-doc like documentation". 
    For more information, please visit the following page: 
    http://www.ebi.ac.uk/seqdb/confluence/display/EV/SQL+documentation

    -i                A SQL file name (Required)
    -fk               An external SQL file name with foreign keys statements (Optional)
    -o                An HTML output file name (Required)
    -d                The name of the database (e.g Core, Variation, Functional Genomics, ...)
    -c                A flag to display the colours associated with the tables (1) or not (0). By default, the value is set to 1.
    -v                Version of the schema. Replace the string ####DB_VERSION#### by the value of the parameter "-v", in the introduction text. (Optional)
    -intro            A html/text file to include in the Introduction section (Optional. If not provided a default text will be inserted)
    -html_head        A html/text file to include extra text inside the html <head></head> tags. (Optional)
    -show_header      A flag to display headers for a group of tables (1) or not (0). By default, the value is set to 1.
    -embed_diagrams   A flag to include schema diagrams as dot graphs
    -sort_headers     A flag to sort (1) or not (0) the headers by alphabetic order. By default, the value is set to 1.
    -sort_tables      A flag to sort (1) or not (0) the tables by alphabetic order. By default, the value is set to 1.
                     
    Other optional options:
    
    # If you want to add some SQL query results as examples:
    -url              URL of the database that has some data
    -skip_connection  Avoid to run the MySQL queries contained in the "@example" tags.

  } . "\n";
  exit(0);
}
