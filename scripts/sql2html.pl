#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2017] EMBL-European Bioinformatics Institute
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
use POSIX;
use Getopt::Long;
use Bio::EnsEMBL::DBSQL::DBAdaptor;


###############
### Options ###
###############

my ($sql_file,$html_file,$db_team,$show_colour,$version,$header_flag,$format_headers,$sort_headers,$sort_tables,$intro_file,$html_head_file,$include_css,$help,$help_format);
my ($host,$port,$dbname,$user,$pass,$skip_conn,$db_handle,$hosts_list);

usage() if (!scalar(@ARGV));
 
GetOptions(
    'i=s' => \$sql_file,
    'o=s' => \$html_file,
    'd=s' => \$db_team,
    'c=i' => \$show_colour,
    'v=i' => \$version,
    'show_header=i'    => \$header_flag,
    'format_headers=i' => \$format_headers,
    'sort_headers=i'   => \$sort_headers,
    'sort_tables=i'    => \$sort_tables,
    'host=s'           => \$host,
    'port=i'           => \$port,
    'dbname=s'         => \$dbname,
    'user=s'           => \$user,
    'pass=s'           => \$pass,
    'hosts_list=s'     => \$hosts_list,
    'skip_connection'  => \$skip_conn,
    'intro=s'          => \$intro_file,
    'html_head=s'      => \$html_head_file,
    'include_css!'     => \$include_css,
    'help!'            => \$help,
    'help_format'      => \$help_format,
);

usage() if ($help);
sql_documentation_format() if ($help_format);


if (!$sql_file) {
  print "> Error! Please give a sql file using the option '-i' \n";
  usage();
}
if (!$html_file) {
  print "> Error! Please give an output file using the option '-o'\n";
  usage();
}

if ($hosts_list && !$user) {
  print "> Error! Please give user name using the option '-user' when you use the option -hosts_list\n";
  usage();
}

$show_colour    = 1 if (!defined($show_colour));
$header_flag    = 1 if (!defined($header_flag));
$format_headers = 1 if (!defined($format_headers));
$sort_headers   = 1 if (!defined($sort_headers));
$sort_tables    = 1 if (!defined($sort_tables));

$skip_conn      = undef if ($skip_conn == 0);

$port ||= 3306;

# Dababase connection (optional)
if (defined($host) && !defined($skip_conn)) {
  my $db_adaptor = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host => $host,
    -user => $user,
    -pass => $pass,
    -port => $port,
    -dbname => $dbname
  ) or die("DATABASE CONNECTION ERROR: Could not get a database adaptor for $dbname on $host:$port\n");
  $db_handle = $db_adaptor->dbc->db_handle;
}




################
### Settings  ##
################

my $default_colour = '#000'; # Black

my %display_col = ('Show' => 'none', 'Hide' => 'inline');
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
my $display = 'Show';
my $parenth_count = 0;
my $header_colour;

my $SQL_LIMIT = 50;
my $img_plus  = qq{<img src="/i/16/plus-button.png" class="sql_schema_icon" alt="show"/>};
my $img_minus = qq{<img src="/i/16/minus-button.png" class="sql_schema_icon" alt="hide"/>};
my $link_text = 'columns';


##############
### Header ###
##############
my $title = 'Schema Documentation';
my $extra_html_head_content = insert_text_into_html_head($html_head_file);

my $css_code = ($include_css) ? get_css_code() : '';

my $html_header = qq{
<html>
<head>
$extra_html_head_content
<title>$title</title>
<meta name="order" content="2" />
$css_code
<script language="Javascript" type="text/javascript">
  var img_plus   = '$img_plus';
  var img_minus  = '$img_minus';

  // Function to show/hide the columns table
  function show_hide (param, a_text) {
  
    // Schema tables
    if (a_text === 'columns') {
      div_id   = '#div_'+param;
      alink_id = '#a_'+param;
    }  
    // Species list
    else if (a_text === 'species') {
      div_id   = '#sp_'+param;
      alink_id = '#s_'+param;
    }
    // Example tables
    else {
      div_id   = '#ex_'+param;
      alink_id = '#e_'+param;
    }
    
    if (\$(div_id).is(':visible')) {
      \$(alink_id).html(img_plus+' Show '+a_text);
    }
    else if (\$(div_id).is(':hidden')) {
      \$(alink_id).html(img_minus+' Hide '+a_text);
    }
    \$(div_id).slideToggle( 300 );
  }
  
  // Function to show/hide all the tables
  function show_hide_all (link_text) {
    expand_div = '#expand';
    div_prefix = 'div_';
    \$("div[id^='"+div_prefix+"']").each(function() {
      param = \$(this).attr('id').substring(div_prefix.length);
      div_id   = '#'+\$(this).attr('id');
      alink_id = '#a_'+param;
      
      if (\$(alink_id)) {
        if (\$(expand_div).val()==0) {
          \$(alink_id).html(img_minus+' Hide '+link_text);
        }
        else {
          \$(alink_id).html(img_plus+' Show '+link_text);
        }
      }
      \$(div_id).slideToggle( 500 );
    });
    if (\$(expand_div).val()==0) {
      \$(expand_div).val(1);
    }
    else {
      \$(expand_div).val(0);
    }
  }
</script>
</head>
<body>
};


##############
### Footer  ##
##############

my $html_footer = qq{
</body>
</html>};




#############
## Parser  ##
#############

# Create a complex hash "%$documentation" to store all the documentation content

open SQLFILE, "< $sql_file" or die "Can't open $sql_file : $!";
while (<SQLFILE>) {
  chomp $_;
  next if ($_ eq '');
  next if ($_ =~ /^\s*(DROP|PARTITION)/i);
  next if ($_ =~ /^\s*(#|--)/); # Escape characters
  
  # Verifications
  if ($_ =~ /^\/\*\*/)  { $in_doc=1; next; }  # start of a table documentation
  if ($_ =~ /^\s*create\s+table\s+(if\s+not\s+exists\s+)?`?(\w+)`?/i) { # start to parse the content of the table
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
      push (@header_names,$header);
      $tables_names->{$header} = [];
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
      
      # Skip the FOREIGN KEY
      next if ($doc =~ /^\s*foreign\s+key/i || $doc =~ /^\s+$/);
      
      if ($doc =~ /^\s*(primary\s+key)\s*\w*\s*\((.+)\)/i or $doc =~ /^\s*(unique)\s*\((.+)\)/i){ # Primary or unique;
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
      elsif ($doc =~ /^\s*(key)\s+\((.+)\)/i) { # Keys
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
          my $line = <SQLFILE>;
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
        $col_def = ($doc =~ /not\s+null/i ) ? '-' : 'NULL';
      }

      add_column_type_and_default_value($col_name,$col_type,$col_def);
    }
  }
}
close(SQLFILE);




###########
## Core  ##
###########

my $html_content;

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

#========================================#
# Display the detailled tables by header #
#========================================#
my $header_id = 1;
foreach my $header_name (@header_names) {
  my $tables = $tables_names->{$header_name};
  my $hcolour = ($documentation->{$header_name}{'colour'}) ? $documentation->{$header_name}{'colour'} : $default_colour;
   
  #----------------#  
  # Header display #
  #----------------#  
  if ($header_flag == 1 and $header_name ne 'default') {
    $html_content .= qq{\n
<div id="header_${header_id}" class="sql_schema_group_header" style="border-color:$hcolour">
  <div class="sql_schema_group_bullet" style="background-color:$hcolour"></div>
  <h2>$header_name</h2>
</div>\n};
    $header_id ++;
    my $header_desc = $documentation->{$header_name}{'desc'};    
    $html_content .= qq{<p class="sql_schema_group_header_desc">$header_desc</p>} if (defined($header_desc));
  }
  
  #------------------------#
  # Additional information #
  #------------------------#
  if ($header_name eq 'default' and defined($documentation->{$header_name}{'info'})) {
    $html_content .= qq{<h2>Additional information about the schema</h2>\n};
  }  
  $html_content .= add_info($documentation->{$header_name}{'info'});
  
  #----------------#
  # Tables display #
  #----------------#
  foreach my $t_name (@{$tables}) {
    my $data = $documentation->{$header_name}{'tables'}{$t_name};
    my $colour = ($header_flag && $hcolour) ? $hcolour : $data->{colour};
    
    $html_content .= qq{<div class="sql_schema_table">};
    $html_content .= add_table_name($t_name,$colour);
    $html_content .= qq{<div class="sql_schema_table_content">};
    $html_content .= add_description($data);
    $html_content .= add_info($data->{info},$data);  
    $html_content .= add_columns($t_name,$data);
    $html_content .= add_examples($t_name,$data);

    # See also + species list
    my $html_table   = add_see($data->{see});
    $html_table     .= add_species_list($t_name,$data->{see}) if ($hosts_list);
    if ($html_table ne '') {
      $html_content .= qq{<table class="sql_schema_extra"><tr>};
      $html_content .= $html_table;
      $html_content .= qq{</tr></table>};
    }
    $html_content .= qq{</div></div>};
  }
}
$html_content .= add_legend();




######################
## HTML/output file ##
######################
open  HTML, "> $html_file" or die "Can't open $html_file : $!";
print HTML $html_header."\n";
print HTML slurp_intro($intro_file)."\n";
print HTML $html_content."\n";
print HTML $html_footer."\n";
close(HTML);
chmod 0755, $html_file;




###############
##  Methods  ##
###############

# List the table names. 
# Group them if the header option "-format_headers" is selected.
# By default there is one group, named "default" and it contains all the tables.
sub display_tables_list {

  my $html; 
  
  $header_flag = 0 if (scalar @header_names == 1);
  
  if ($header_flag == 1) {
    $html .= qq{\n<h3 id="top">List of the tables:</h3>\n};
    $html .= qq{<div>\n} if ($format_headers == 1);
  } 
  else {
    my $list_width;
    if (scalar @header_names == 1) {
      my $list_count = scalar @{$tables_names->{'default'}};
      my $list_nb_col = ceil($list_count/$nb_by_col);
      $list_width = length_names($tables_names->{'default'},$list_nb_col);
    }
    $html .= qq{
<div>      
  <div id="top" class="sql_schema_table_list_nh" style="$list_width">
    <div class="sql_schema_table_list_sub_nh">
      <img src="/i/16/rev/info.png" style="vertical-align:top" />
      <h3>List of the tables:</h3>
    </div>};
  }
  
  my $has_header = 0;
  my $nb_col_line = 0;
  
  foreach my $header_name (@header_names) {
    
    my $tables = $tables_names->{$header_name};
    my $count = scalar @{$tables};
    next if ($count == 0);
    
    # Number of columns needed to display the tables of the group
    my $nb_col = ceil($count/$nb_by_col);
    my $nbc = $nb_col;
    my $table_count = 0;
    my $col_count = 1;
  
    if ($nb_col>3) { 
      while ($nb_col>3) {
        $nb_by_col += 5;
        $nb_col = ceil($count/$nb_by_col);
      }
      $nb_col = 3;
    }
    
    
    # Header #
    if ($header_flag == 1) {
      if ($header_name ne 'default') {
        if ($nb_col_line+$nbc > 4 and $format_headers == 1) {
          $html .= qq{  <div style="clear:both"></div>\n</div>\n\n<div>};
          $nb_col_line = 0;
        }
      
        $html .= display_header($header_name,$nbc);
        $nb_col_line += $nbc;
        $has_header = 1;
      }
      
      # List of tables #
      $html .= qq{\n      <div style="float:left">} if ($count > $nb_by_col);
      $html .= qq{\n      <ul class="sql_schema_table_list">\n};
      my $t_count = 0;
      foreach my $t_name (@{$tables}) {
        if ($t_count>=$nb_by_col) {
          $html .= qq{\n      </ul>\n      </div>};
          $html .= qq{\n      <div style="float:left">};
          $html .= qq{\n      <ul class="sql_schema_table_list">\n};
          $t_count = 0;
        }
        my $t_colour;
        if ($has_header == 0 && $show_colour) {
          $t_colour = $documentation->{$header_name}{'tables'}{$t_name}{'colour'};
          $t_colour = $default_colour if (!defined($t_colour) || $t_colour eq '');
        }
        $html .= add_table_name_to_list($t_name,$t_colour);
        $t_count++;
      }
      $html .= qq{\n      </ul>};
      $html .= qq{\n      </div>} if ($count > $nb_by_col);
      $html .= qq{\n    </div>\n} if ($format_headers == 1);   
    }
    else {
      $html .= qq{\n    <table><tr><td>\n      <ul class="sql_schema_table_list_nh">\n};

      # List of tables #
      foreach my $t_name (@{$tables}) {
        if ($table_count == $nb_by_col and $col_count<$nb_col and $nb_col>1){
          $html .= qq{      </ul>\n    </td><td>\n      <ul class="sql_schema_table_list_nh">\n};
          $table_count = 0;
        }
        my $t_colour = $default_colour;
        if ($has_header == 0 && $show_colour) {
          $t_colour = $documentation->{$header_name}{'tables'}{$t_name}{'colour'} if ($documentation->{$header_name}{'tables'}{$t_name}{'colour'});
        }

        $html .= add_table_name_to_list($t_name,$t_colour);
        $table_count ++;
      }
      $html .= qq{      </ul>\n    </td></tr></table>\n};
    }
  }
  
  my $input_margin;
  if ($header_flag == 1 and $format_headers == 1){
    $html .= qq{\n  <div style="clear:both" />\n</div>};
  } else {
    $input_margin = qq{ style="margin-left:10px;margin-bottom:5px"};
  }
  $html .= qq{
  <input type="button" onclick="show_hide_all('$link_text')" class="fbutton" value="Show/hide all"$input_margin/>
  <input type="hidden" id="expand" value="0" />
  };
  
  $html .= qq{\n  </div>\n  <div style="clear:both" />\n</div>} if ($header_flag!=1 and $format_headers == 1);
  
  return $html;
}


# If the option "-show_header" is selected, the tables will be displayed by group ("Header") in the HTML page.
# This method generates the HTML code to display the group names & descriptions.
sub display_header {
  my $header_name = shift;
  my $nb_col = shift;
  
  my $html;
  
  if ($format_headers == 1) {
  
    my $hcolour = $default_colour;
    if ($show_colour && $header_colour) {
      $hcolour = $documentation->{$header_name}{colour} if ($documentation->{$header_name}{colour});
    }

    $html .= qq{
  <div class="sql_schema_table_group">
    <div class="sql_schema_table_group_header" style="border-color:$hcolour">
      <div class="sql_schema_table_group_bullet" style="background-color:$hcolour"></div>
      <h2>$header_name</h2>
    </div>};
  } 
  else {
    $html .= qq{    <h2>$header_name</h2>};
  }
  return $html;
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
        $documentation->{$header}{'desc'} = escape_html($tag_content);
      }
      # Table description
      else {
        $documentation->{$header}{'tables'}{$table}{$tag} = escape_html($tag_content);
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
  # New tag initialized
  if ($t1) {
    $tag = $t1;
    $tag_content = $t2;
  }
  else {
    $tag = $tag_content = '';  
  }
}
 

# Method generating the HTML code to display the table name into the top menu.
sub add_table_name_to_list {
  my $t_name = shift;
  my $t_colour = shift;
  my $c = $t_colour;
  if (defined($t_colour)) {
    $t_colour = ($t_colour ne '') ? qq{ style="background-color:$t_colour"} : '';
    $t_colour = qq{<div class="sql_schema_table_name_nh"$t_colour>&nbsp;</div> };
  }
  my $html = qq{        <li>$t_colour<a href="#$t_name" class="sql_schema_link" style="font-weight:bold">$t_name</a></li>\n};
  return $html;
}


# Method generating the HTML code to display the title/header of the table description block
sub add_table_name {
  my $t_name = shift;
  my $colour = shift || $default_colour;

  my $html = qq{
  <div id="$t_name" class="sql_schema_table_header" style="border-top-color:$colour">
    <div class="sql_schema_table_header_left"><span style="background-color:$colour"></span>$t_name</div>
    <div class="sql_schema_table_header_right">
  };
  $html .= show_hide_button("a_$t_name", $t_name, $link_text);
  $html .= qq{
      <span class="sql_schema_table_separator"> </span> <a href="#top" class="sql_schema_link">[Back to top]</a>
    </div>
    <div style="clear:both"></div>
  </div>\n}; 
  return $html;
}


# Method generating the HTML code to display the description content
sub add_description {
  my $data = shift;
  
  # Search if there are some @link tags in the description text.
  my $desc = add_internal_link($data->{desc},$data);
  
  return qq{  <p class="sql_schema_table_desc">$desc</p>\n};
}


# Method generating the HTML code to display additional information contained in the tags @info
sub add_info {
  my $infos = shift;
  my $data  = shift;
  my $html  = '';
  
  foreach my $inf (@{$infos}) {
    my ($title,$content) = split('@info@', $inf);
    $content = add_internal_link($content,$data) if (defined($data));
    
    $html .= qq{
    <table>
      <tr class="bg3"><th>$title</th></tr>
      <tr class="bg1"><td>$content</td></tr>
    </table>\n};
  }
  
  return $html;
}


# Method generating the HTML code of the table listing the columns of the given SQL table.
sub add_columns {
  my $table = shift;
  my $data  = shift;
  my $cols  = $data->{column};
  my $display_style = $display_col{$display};
  
  my $html = qq{\n  <div id="div_$table" style="display:$display_style">
    <table class="ss sql_schema_table_column">
      <tr class="center">
        <th>Column</th>
        <th>Type</th>
        <th class="val">Default value</th>
        <th class="desc">Description</th>
        <th class="index">Index</th>
      </tr>\n};
  my $bg = 1;
  
  foreach my $col (@$cols) {
    my $name    = $col->{name};
    my $type    = $col->{type};
    my $default = $col->{default};
    my $desc    = $col->{desc};
    my $index   = $col->{index};
    
    # links
    $desc = add_internal_link($desc,$data);
    
    $type = parse_column_type($type);
    
    $html .= qq{
      <tr>
        <td class="bg$bg"><b>$name</b></td>
        <td class="bg$bg">$type</td>
        <td class="bg$bg">$default</td>
        <td class="bg$bg">$desc</td>
        <td class="bg$bg">$index</td>
      </tr>\n};
    if ($bg==1) { $bg=2; }
    else { $bg=1; }
  }
  $html .= qq {    </table>\n  </div>\n};
  
  return $html;
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
    $html .= qq{<div class="sql_schema_table_examples"><p class="sql_schema_table_example_header">Example$nb_display:</p><div class="sql_schema_table_example_content">};
    my $has_desc = 0;
    my $sql;
    
    # Parse the example lines
    foreach my $line (@lines) {
      chomp($line);
      
      # Pick up the SQl query if it exists
      if ($line =~ /(.*)\s*\@sql\s*(.+)/) {
        $html .= ($has_desc == 1) ? $1 : qq{<p>$1};
        $sql = $2;
      } elsif (!defined($sql)){
        $html .= qq{<p>} if ($has_desc == 0);
        $html .= $line;
        $has_desc = 1;
      }
      else {
        $sql .= $line;
      }
    }
    $html .= qq{</p>};
    
    # Search if there are some @link tags in the example description.
    $html = add_internal_link($html,$data);
    
    # Add a table of examples
    if (defined($sql)) {
      my $show_hide = '';
      my $sql_table = '';
      if (!defined($skip_conn) && defined($host)) {
        $show_hide .= show_hide_button("e_$table$nb", "$table$nb", 'query results');
        $sql_table = get_example_table($sql,$table,$nb);
      }
      $sql = escape_html($sql);
             
        foreach my $word (qw(SELECT DISTINCT COUNT CONCAT GROUP_CONCAT AS FROM LEFT JOIN USING WHERE AND OR ON IN LIMIT DESC ORDER GROUP BY)) {
          my $hl_word = qq{<span class="sql_schema_sql_highlight">$word</span>};
          $sql =~ s/$word /$hl_word /ig;
        }
      $html .= qq{
      <div>
        <div class="sql_schema_table_example_query">
          <pre>$sql</pre>
        </div>
        <div class="sql_schema_table_example_button">$show_hide</div>
        <div style="clear:both"></div>
      </div>
      $sql_table};
    }
    $html .= qq{</div></div>};
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


# Display the list of species where the given table is populated
sub add_species_list {
  my $table   = shift;
  my $has_see = shift;

  my $db_type = lc($db_team);
  my $sql = qq{SELECT table_schema FROM information_schema.tables WHERE table_rows>=1 AND 
               TABLE_SCHEMA like '%$db_type\_$version%' AND TABLE_NAME='$table'};

  my @species_list;
  foreach my $hostname (split(',',$hosts_list)) {
    my $db_type = lc($db_team);
    my $sth = get_connection_and_query("", $hostname, $sql);

    # loop over databases
    while (my ($dbname) = $sth->fetchrow_array) {
      next if ($dbname =~ /^master_schema/);

      $dbname =~ /^(.+)_$db_type/;
      my $s_name = $1;

      push(@species_list, $s_name);
    }
  }
  return '' if (!@species_list);

  my $show_hide = show_hide_button("s_$table", "$table", 'species');

  my $separator = (defined($has_see) && scalar(keys(@$has_see))) ? qq{  <td class="sql_schema_extra_separator"></td>} : '';
  my $margin = (defined($has_see) && scalar(keys(@$has_see))) ? qq{ style="padding-left:25px"} : '';

  my $html = qq{$separator
  <td class="sql_schema_extra_right"$margin><p><span>List of species with populated data:</span>$show_hide</p>
    <div id="sp_$table" style="display:none;">};
      
  @species_list = map{ $_ =~ s/_/ /g; $_ } @species_list;
  @species_list = map { qq{<li class="sql_schema_species_name">}.ucfirst($_)."</li>" } @species_list;
  
  $html .= qq{      <ul>\n        }.join("\n        ",@species_list).qq{\n      </ul>\n};
  $html .= qq{    </div>\n  </td>};
  
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
    my $table_to_link = qq{<a href="#$link" class="sql_schema_link">$link</a>};
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
    $index .= ": <i>$idx_name</i>";
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
          $col->{index} .= '<br />';
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
  $c_data =~ s/<br \/>//g;
  
  my @items_list = split(',',$c_data);
  
  return $type unless (scalar(@items_list) > 1);
  
  my $data_list = qq{$c_type:<ul class="sql_schema_table_column_type">};
  foreach my $item (@items_list) {
    $data_list .= qq{  <li>$item</li>};
  }
  $data_list .= qq{</ul>};
  return $data_list;
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
  my @tcols;
     
  foreach my $col (split(',',$cols)) {
  
    # Columns selection like the expressions "table.*" or "*"
    my $table_name;
    $table_name = $table if ($cols eq '*');
    $table_name = $1 if ($col =~ /(\S+)\.\*/ and !defined($table_name));
    if (defined($table_name)) {
      my $table_cols = $db_handle->selectall_arrayref(qq{SHOW COLUMNS FROM $table_name});
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
  
  my $results = $db_handle->selectall_arrayref($sql);
  if (scalar(@$results)) {
    $html .= qq{
  <div id="ex_$table$nb" style="display:none;">
    <table class="ss sql_schema_table_example_result">\n      <tr><th>};
    $html .= join("</th><th>",@tcols);
    $html .= qq{</th></tr>};
    
    my $bg = '';
    
    my $count = 0;
    foreach my $result (@$results) {
      last if ($count >= $SQL_LIMIT);
      $html .= qq{      <tr$bg><td>};
      $html .= join("</td><td>", @$result);
      $html .= qq{</td></tr>};
      
      $bg = ($bg eq '')  ? ' class="bg2"' : '';  
      $count ++;
    }
    $html .= qq{    </table>\n  </div>};
  } else {
    my $msg = qq{ERROR: the SQL query displayed above returned no results!};
    $html .= qq{<div class="sql_schema_table_example_error">$msg</div>};
    print STDERR qq{SQL: $sql\n$msg\n};
  }
  
  return $html;
}


# Method generating a "Colour legend" paragraph, based on the header colours.
sub add_legend {
  my $html = '';
  my $default = 'Other tables';
  
  return $html if (scalar @colours == 1 or $header_colour);
  
  $html .= qq{<br />\n<hr />\n<h3 id="legend">Colour legend</h3>\n<table>};
  
  foreach my $c (@colours) {
    my $desc = '';
    if ($c eq $default_colour && !$legend{$default_colour}) {
      $desc = $default;
    }
    else {
      $desc = $legend{$c};
    }
    $html .= qq{  <tr><td class="sql_schema_legend" style="background-color:$c"></td><td>$desc</td></tr>\n};
  }
  $html .= qq{</table>};
  
  return $html;
}


# Removed the character(s) ` from the read line.
sub remove_char {
  my $text = shift;
  $text =~ s/`//g;
  return $text;
}


# Escape special character for the HTML output
# Code taken from HTML::Escape::PurePerl
sub escape_html {
    my $str = shift;
    return '' unless defined $str;
    my %_escape_table = ( '&' => '&amp;', '>' => '&gt;', '<' => '&lt;', q{"} => '&quot;', q{'} => '&#39;', q{`} => '&#96;', '{' => '&#123;', '}' => '&#125;' );
    $str =~ s/([&><"'`{}])/$_escape_table{$1}/ge;
    
    # Revert escape for some HTML characters (e.g. <br> and <a> tags)
    my %_revert_escape_table = ( '&lt;br \/&gt;' => '<br />', '&lt;br\/&gt;' => '<br />', '&lt;a href=&quot;' => '<a href="', '&quot;&gt;' => '">', '&lt;\/a&gt;' => '</a>');
    foreach my $char (keys(%_revert_escape_table)) {
      $str =~ s/$char/$_revert_escape_table{$char}/g;
    }
    
    return $str;
}


# Insert text into the <head> tags
sub insert_text_into_html_head {
  my $header_file = shift;
  return '' if (!defined $header_file);

  local $/=undef;
  open my $fh, "< $header_file" or die "Can't open $header_file: $!";
  my $header_html = <$fh>;
  close $fh;
  return $header_html;
}


# Insert the introduction text of the web page
sub slurp_intro {
  my $intro_file = shift;
  return qq{<h1>Ensembl $db_team Schema Documentation</h1>\n<h2>Introduction</h2>\n<p><i>please, insert your introduction here</i><p><br />} if (!defined $intro_file);

  local $/=undef;
  open my $fh, "< $intro_file" or die "Can't open $intro_file: $!";
  my $intro_html = <$fh>;
  close $fh;
  
  $intro_html =~ s/####DB_VERSION####/$version/g if (defined($version));
  
  return $intro_html;
}


# Show/hide button
sub show_hide_button {
  my $a_id   = shift;
  my $div_id = shift;
  my $label  = shift;
  
  my $show_hide = qq{
  <a id="$a_id" class="help-header sql_schema_show_hide" onclick="show_hide('$div_id','$label')">
    $img_plus Show $label
  </a>};
  return $show_hide;
}


# Connects and execute a query
sub get_connection_and_query {
  my $dbname = shift;
  my $hname  = shift;
  my $sql    = shift;
  my $params = shift;

  my ($host, $port) = split /\:/, $hname;

  # DBI connection
  my $dsn = "DBI:mysql:$dbname:$host:$port";
  my $dbh = DBI->connect($dsn, $user, $pass) or die "Connection failed";

  my $sth = $dbh->prepare($sql);
  if ($params) {
    $sth->execute(join(',',@$params));
  }
  else {
    $sth->execute;
  }
  return $sth;
}


sub get_css_code() {
  my $css = qq{
<style type="text/css">
  /* Icons */
  img.sql_schema_icon { width:12px;height:12px;position:relative;top:2px; }

  /* Tables list - with header */
  div.sql_schema_table_group           { background-color:#F4F4F4;border-left:1px dotted #BBB;border-right:1px dotted #BBB;border-bottom:1px dotted #BBB;margin-bottom:15px;float:left;margin-right:20px;min-width:200px; }
  div.sql_schema_table_group_header    { background-color:#FFF;padding:2px 5px;border-top:2px solid #000;border-bottom:1px solid #000; }
  div.sql_schema_table_group_bullet    { box-shadow:1px 1px 2px #888;padding:0px 8px;display:inline;vertical-align:middle; }
  div.sql_schema_table_group_header h2 { margin-left:8px;display:inline;color:#000;vertical-align:middle; }
  ul.sql_schema_table_list             { padding:0px 4px 0px 22px;margin-bottom:2px; }
  ul.sql_schema_table_list li          { margin-right:0px; }

  /* Tables list - no header */
  div.sql_schema_table_list_nh       { background-color:#F4F4F4;border-radius:5px;margin-bottom:20px;float:left; }
  div.sql_schema_table_list_sub_nh   { padding:5px;background-color:#336;border-top-left-radius:5px;border-top-right-radius:5px; }
  div.sql_schema_table_list_nh h3    { display:inline;color:#FFF; }
  div.sql_schema_table_list_nh table { padding:0px 2px; }
  ul.sql_schema_table_list_nh        { padding-left:20px; }
  div.sql_schema_table_name_nh       {padding:0px;margin-left:0px;display:inline; }

  /* Group header */
  div.sql_schema_group_header    { background-color:#F4F4F4;padding:5px 4px;margin:75px 0px 5px;border-top:2px solid #000;border-bottom:1px solid #000; }
  div.sql_schema_group_bullet    { box-shadow:1px 1px 2px #888;padding:0px 8px;display:inline;vertical-align:top; }
  div.sql_schema_group_header h2 { display:inline;color:#000;padding-top:0px;margin-left:6px; }
  p.sql_schema_group_header_desc { width:800px; }

  /* SQL table header */
  div.sql_schema_table                  { max-width:90%;border-left:1px dotted #BBB;border-right:1px dotted #BBB;border-bottom:1px dotted #BBB; }
  div.sql_schema_table_header           { background-color:#F4F4F4;border-bottom:1px solid #BBB;margin-top:60px;padding:4px;border-top:1px solid #000; }
  div.sql_schema_table_header_left      { float:left;text-align:left;font-size:11pt;font-weight:bold;color:#000;padding:2px 1px; }
  div.sql_schema_table_header_left span { display:inline-block;height:10px;width:10px;border-radius:5px;margin-right:5px;box-shadow:1px 1px 2px #888;vertical-align:middle; }
  div.sql_schema_table_header_right     { float:right;text-align:right;padding:2px 1px;margin-right:8px; }
  div.sql_schema_table_content          { padding:10px; }
  span.sql_schema_table_separator       { margin-right:8px;border-right:1px solid #000; }

  /* SQL table description */
  p.sql_schema_table_desc { padding:5px 0px;margin-bottom:0px; }

  /* SQL table columns */
  table.sql_schema_table_column          { border:1px solid #667aa6;border-spacing:2px; }
  table.sql_schema_table_column th       { background-color:#667aa6;color:#FFF;padding:2px; }
  table.sql_schema_table_column th.val   { min-width:80px; }
  table.sql_schema_table_column th.desc  { min-width:250px; }
  table.sql_schema_table_column th.index { min-width:100px; }
  ul.sql_schema_table_column_type        { margin-bottom:0px; }
  ul.sql_schema_table_column_type li     { line-height:12px; }

  /* SQL table examples */
  div.sql_schema_table_examples          { margin:10px 0px 15px; }
  p.sql_schema_table_example_header      { font-weight:bold;margin-bottom:10px; }
  div.sql_schema_table_example_content   { margin-left:10px; }
  div.sql_schema_table_example_query     { float:left;border:1px solid #555;padding:2px 4px;margin-right:15px;overflow:auto;max-width:90%;background-color:#FAFAFA; }
  div.sql_schema_table_example_query pre { margin-bottom:0px;color:#333; }
  div.sql_schema_table_example_button    { float:left; }
  table.sql_schema_table_example_result  { width:90%;margin-top:20px;border-spacing:2px; }
  div.sql_schema_table_example_error     { padding:5px;margin:10px;width:500px;font-weight:bold;border:2px solid red;color:red; }
  span.sql_schema_sql_highlight          { color:#00F; }

  /* SQL table extra info */
  table.sql_schema_extra         { margin-top:20px;border:1px solid #BBB; }
  table.sql_schema_extra a       { text-decoration:none; }
  td.sql_schema_extra_left       { padding: 4px 25px 0px 2px }
  td.sql_schema_extra_left ul    { margin-bottom:0px; }
  td.sql_schema_extra_right      { padding-top:4px; }
  td.sql_schema_extra_right p    { margin-bottom:0px; }
  td.sql_schema_extra_right span { margin-right:10px;font-weight:bold; }
  td.sql_schema_extra_right ul   { margin-top:1em; } 
  td.sql_schema_extra_separator  { margin:0px;padding:0px;width:1px;border-right:1px dotted #BBB; }
  .sql_schema_species_name       { font-style:italic; }

  /* Legend */
  .sql_schema_legend { width:25px;height:15px; }

  /* Links */
  a.sql_schema_link { text-decoration:none; }
  a.sql_schema_show_hide { cursor:pointer;font-weight:bold;border-radius:5px;background-color:#FFF;border:1px solid #667aa6;padding:1px 2px;margin-right:8px;vertical-align:middle;box-shadow:1px 1px 2px #888; }
  .sql_schema_legend { width:25px;height:15px;}
</style>  
  };

  return $css;
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
    -o                An HTML output file name (Required)
    -d                The name of the database (e.g Core, Variation, Functional Genomics, ...)
    -c                A flag to display the colours associated with the tables (1) or not (0). By default, the value is set to 1.
    -v                Version of the schema. Replace the string ####DB_VERSION#### by the value of the parameter "-v", in the introduction text. (Optional)
    -intro            A html/text file to include in the Introduction section (Optional. If not provided a default text will be inserted)
    -html_head        A html/text file to include extra text inside the html <head></head> tags. (Optional)
    -show_header      A flag to display headers for a group of tables (1) or not (0). By default, the value is set to 1.
    -format_headers   A flag to display formatted headers for a group of tables (1) or not (0) in the top menu list. By default, the value is set to 1.                
    -sort_headers     A flag to sort (1) or not (0) the headers by alphabetic order. By default, the value is set to 1.
    -sort_tables      A flag to sort (1) or not (0) the tables by alphabetic order. By default, the value is set to 1.
                     
    Other optional options:
    
    # If you want to add some SQL query results as examples:
    -host             Host name of the MySQL server
    -port             Port of the MySQL server
    -dbname           Database name
    -user             MySQL user name
    -pass             MySQL password (not always required)
    -skip_connection  Avoid to run the MySQL queries contained in the "@example" tags.
    
    # If you want to show, for each table, the list of species where it has been populated:
    -hosts_list       The list of host names where the databases are stored, separated by a coma,
                      e.g. ensembldb.ensembl.org1, ensembldb.ensembl.org2
                      You will need to provide at least the parameter -user (-port and -pass are not mandatory)

  } . "\n";
  exit(0);
}
