
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

####################################################################
## Sphinx extension to generate analysis diagrams from pipeconfigs #
####################################################################

# Use like this in your RestructuredText document
#
# .. hive_diagram::
#
#     {   -logic_name => 'A',
#         -flow_into  => {
#            1 => [ 'B' ],
#         },
#     },
#     {   -logic_name => 'B',
#     },
#
# The directive will show side-by-side the pipeconfig code and the
# diagram it models

# For python2 compatibility
from __future__ import print_function

import json
import os.path
import subprocess
import sys
import tempfile

from docutils import nodes
from docutils.parsers.rst import Directive
from docutils.parsers.rst.directives import tables

from sphinx.ext.graphviz import graphviz


class HiveDiagramDirective(tables.ListTable):

    # defines the parameter the directive expects
    required_arguments = 0
    optional_arguments = 0
    final_argument_whitespace = False
    has_content = True
    add_index = True

    def run(self):

        # The PipeConfig sample is shown in a literal block
        content = '\n'.join(self.content)
        code_block_node = nodes.literal_block(text=content)

        # We reuse the graphviz node (from the graphviz extension) as it deals better with image formats vs builders
        graphviz_node = graphviz()
        graphviz_node['code'] = generate_dot_diagram(content)
        graphviz_node['options'] = {}

        table = [[[code_block_node], [graphviz_node]]]
        table_node = self.build_table_from_list(table, [50,50], 0, 0)
        return [table_node]


pipeconfig_template = """
package %s;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;  # For INPUT_PLUS, WHEN and ELSE
use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

sub pipeline_analyses {
    my ($self) = @_;
    my $all_analyses = [%s];
    map {$_->{-module} = 'Bio::EnsEMBL::Hive::RunnableDB::Dummy'} @$all_analyses;
    return $all_analyses;
}

1;
"""

display_config_json = json.dumps( {
    "Graph": {
        "Pad": 0,
        "DisplayStats": 0,
        "DisplayDBIDs": 0,
        "DisplayDetails": 0,
    }
} )


json_filename = None
pipeconfig_filename = None

def generate_dot_diagram(pipeconfig_content):

    # A temporary file for the JSON config
    global json_filename
    if json_filename is None:
        json_fh = tempfile.NamedTemporaryFile(mode='w+', dir="_build", delete=False)
        print(display_config_json, file=json_fh)
        json_fh.close()
        json_filename = json_fh.name

    # eHive's default configuration file
    default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"

    # A temporary file for the sample PipeConfig
    global pipeconfig_filename
    if pipeconfig_filename is None:
        pipeconfig_fh = tempfile.NamedTemporaryFile(mode='w+', suffix='.pm', dir="_build", delete=False)
        pipeconfig_filename = pipeconfig_fh.name
    else:
        pipeconfig_fh = open(pipeconfig_filename, "w")

    package_name = "_build::" + os.path.basename(pipeconfig_fh.name)[:-3]
    print(pipeconfig_template % (package_name, pipeconfig_content), file=pipeconfig_fh)
    pipeconfig_fh.close()

    # Run generate_graph and read the content of the dot file
    graph_path = os.path.join(os.environ["EHIVE_ROOT_DIR"], "scripts", "generate_graph.pl")
    if os.environ["PERL5LIB"][-2:] != ":.":
        os.environ["PERL5LIB"] = os.environ["PERL5LIB"] + ":."
    dotcontent = subprocess.check_output([graph_path, "-pipeconfig", pipeconfig_fh.name, "--format", "dot", "-config_file", default_config_file, "-config_file", json_filename], stderr=sys.stderr)

    return dotcontent.decode()


def cleanup_tmp_files(app, exception):
    if json_filename is not None:
        os.remove(json_filename)
    if pipeconfig_filename is not None:
        os.remove(pipeconfig_filename)


## Register the extension
def setup(app):
    app.add_directive('hive_diagram', HiveDiagramDirective)
    app.connect('build-finished', cleanup_tmp_files)

