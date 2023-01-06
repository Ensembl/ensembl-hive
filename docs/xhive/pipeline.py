
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2023] EMBL-European Bioinformatics Institute
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

#################################################################
## Sphinx extension to initialize, run and snapshot a pipeline ##
#################################################################

# Use like this in your RestructuredText document
#
# * To initialize a pipeline and give it the "lm" name
#   (tweaks are optional).
#
#   .. hive_pipeline:: lm init Bio::EnsEMBL::Hive::Examples::LongMult::PipeConfig::LongMult_conf
#      :tweaks: pipeline.param[take_time]=0
#
#
# * To run a job
#
#   .. hive_pipeline:: lm run_job 1
#
#
# * To sync the whole pipeline
#
#   .. hive_pipeline:: lm sync
#
#
# * To sync some analyses
#
#   .. hive_pipeline:: lm sync
#      :analyses_pattern: add_together
#
# * To include a job-diagram snapshot. Add "vj_options" to pass extra command-line parameters
#
#   .. hive_pipeline:: lm job_diagram
#      :vj_options: -include -accu_keys
#
#
# * To include an analysis-diagram snapshot
#
#   .. hive_pipeline:: lm analysis_diagram
#
# A SQLite database is created when init_pipeline is called, and dropped at the end of the Sphinx build
#



import os
import subprocess
import sys
import tempfile

from docutils import nodes
from docutils.parsers.rst import Directive
from docutils.parsers.rst import directives

from sphinx.ext.graphviz import graphviz

allowed_commands = frozenset(['init', 'run_job', 'sync', 'analysis_diagram', 'job_diagram'])
ehive_db_urls = {}

class HivePipelineDirective(Directive):

    # defines the parameter the directive expects
    required_arguments = 2
    optional_arguments = 1
    final_argument_whitespace = False
    has_content = False
    add_index = True

    option_spec = {
            'tweaks': directives.unchanged,
            'analyses_pattern': directives.unchanged,
            'vj_options': directives.unchanged,
            }

    def run(self):
        name = self.arguments[0]
        command = directives.choice(self.arguments[1], allowed_commands)

        if command == 'init':
            # Create a temporary file to hold the database
            db_fh = tempfile.NamedTemporaryFile(delete = False)
            ehive_db_urls[name] = 'sqlite:///' + db_fh.name
            command_array = ['init_pipeline.pl', self.arguments[2], '-pipeline_url', ehive_db_urls[name]]
            for tweak in self.options.get('tweaks', '').split():
                command_array.extend(['-tweak', tweak])
        else:
            db = ehive_db_urls[name]
            if command == 'run_job':
                command_array = ['runWorker.pl', '-url', db, '-job_id', self.arguments[2]]

            elif command == 'sync':
                command_array = ['beekeeper.pl', '-url', db, '-sync']
                if self.options.has_key('analyses_pattern'):
                    command_array.extend(['-analyses_pattern', self.options['analyses_pattern']])

            elif command == 'analysis_diagram':
                default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"
                command_array = ['generate_graph.pl', '-url', db, '-output', '/dev/stdout', '-format', 'dot', '-config_file', default_config_file]

            elif command == 'job_diagram':
                default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"
                command_array = ['visualize_jobs.pl', '-url', db, '-output', '/dev/stdout', '-format', 'dot', '-config_file', default_config_file]
                command_array.extend(self.options.get('vj_options', '').split())

        command_array[0] = os.path.join(os.environ["EHIVE_ROOT_DIR"], 'scripts', command_array[0])
        dotcontent = subprocess.check_output(command_array, stderr=sys.stderr)

        if command.endswith('diagram'):
            # We reuse the graphviz node (from the graphviz extension) as it deals better with image formats vs builders
            graphviz_node = graphviz()
            graphviz_node['code'] = dotcontent
            graphviz_node['options'] = {}

            return [graphviz_node]
        else:
            return []

def cleanup_dbs(app, exception):
    for url in ehive_db_urls.values():
        os.remove(url[10:])

## Register the extension
def setup(app):
    # Register the directive
    app.add_directive('hive_pipeline', HivePipelineDirective)
    app.connect('build-finished', cleanup_dbs)

