
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
# * To include a job-diagram snapshot
#
#   .. hive_pipeline:: lm job_diagram
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
            }

    def run(self):
        name = self.arguments[0]
        command = directives.choice(self.arguments[1], allowed_commands)
        dot_fh = None

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
                dot_fh = tempfile.NamedTemporaryFile(delete = False, dir = os.getcwd(), suffix = '.dot')
                default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"
                command_array = ['generate_graph.pl', '-url', db, '-output', dot_fh.name, '-config_file', default_config_file]

            elif command == 'job_diagram':
                dot_fh = tempfile.NamedTemporaryFile(delete = False, dir = os.getcwd(), suffix = '.dot')
                default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"
                command_array = ['visualize_jobs.pl', '-url', db, '-output', dot_fh.name, '-config_file', default_config_file]

        command_array[0] = os.path.join(os.environ["EHIVE_ROOT_DIR"], 'scripts', command_array[0])
        subprocess.check_call(command_array, stdout=sys.stdout, stderr=sys.stderr)

        if dot_fh is None:
            return []
        else:
            # Read the .dot content to initialize the graphviz directive
            dotcontent = dot_fh.read()
            dot_fh.close()
            os.remove(dot_fh.name)

            # We reuse the graphviz node (from the graphviz extension) as it deals better with image formats vs builders
            graphviz_node = graphviz()
            graphviz_node['code'] = dotcontent
            graphviz_node['options'] = {}

            return [graphviz_node]


## Register the extension
def setup(app):
    # Register the directive
    app.add_directive('hive_pipeline', HivePipelineDirective)

