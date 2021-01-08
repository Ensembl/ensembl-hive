
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2021] EMBL-European Bioinformatics Institute
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

#####################################################
## Sphinx extension to generate code documentation ##
#####################################################

# The extension provides various directives to embed
# dynamically-generated RestructuredText content from
# the code-base itself
#
# * Schema documentation. This runs sql2rst on the given
#   schema definition files
#
#   .. schema_documentation:: $EHIVE_ROOT_DIR/sql/tables.mysql
#      :foreign_keys: $EHIVE_ROOT_DIR/sql/foreign_keys.sql
#      :title: Hive
#      :embed_diagrams:
#


import errno
import json
import os
import os.path
import pickle
import subprocess
import sys

from docutils import io, nodes, statemachine
from docutils.parsers.rst import Directive, directives


# Shamelessly stolen from six
if (sys.version_info[0] == 3):
    string_type = str
else:
    string_type = basestring


class IncludeCommand(Directive):
    required_arguments = 0
    option_spec = {
            'command': directives.unchanged,
            }

    def run(self):
        content = self.get_content()
        try:
            docutils_input = io.StringInput(source=content)
            rawtext = docutils_input.read()
        except IOError as error:
            # Show the content
            raise self.severe(u'Problems with "%s" command:\n%s.' % ''.join(self.options['command']), ErrorString(error))
        include_lines = statemachine.string2lines(rawtext, 4, convert_whitespace=True)
        self.state_machine.insert_input(include_lines, 'CMD')
        return []

    def get_command(self):
        return self.options['command']

    def get_content(self):
        command = self.get_command()
        if isinstance(command, string_type):
            return subprocess.check_output(command, stderr=sys.stderr, shell=True)
        else:
            return subprocess.check_output(command, stderr=sys.stderr)


class SchemaDocumentation(IncludeCommand):

    required_arguments = 1
    optional_arguments = 0
    final_argument_whitespace = False
    option_spec = {
            'foreign_keys' : directives.unchanged,
            'title' : directives.unchanged,
            'sort_headers' : directives.unchanged,
            'sort_tables' : directives.unchanged,
            'intro' : directives.unchanged,
            'url' : directives.unchanged,
            'embed_diagrams' : directives.flag,
            'cached' : directives.flag,
            }

    # Where to keep the cached outputs
    cache_filename = os.path.join("_build", "rtd_cache.pickle")

    def get_command(self):
        command = [
                os.path.join(os.environ["EHIVE_ROOT_DIR"], "scripts", "dev", "sql2rst.pl"),
                '-i', self.arguments[0].replace('$EHIVE_ROOT_DIR', os.environ["EHIVE_ROOT_DIR"]),
                ]
        self.state.document.settings.record_dependencies.add(command[0], command[2])
        if 'foreign_keys' in self.options:
            foreign_keys_path = self.options['foreign_keys'].replace('$EHIVE_ROOT_DIR', os.environ["EHIVE_ROOT_DIR"])
            self.state.document.settings.record_dependencies.add(foreign_keys_path)
            command.extend( ['--fk', foreign_keys_path] )
        for flag in ['embed_diagrams']:
            if flag in self.options:
                command.extend( ['--' + flag] )
        for param in ['sort_headers', 'sort_tables', 'url']:
            if param in self.options:
                command.extend( ['--' + param, self.options[param]] )
        if 'intro' in self.options:
            command.extend( ['--intro', self.options['intro'].replace('$EHIVE_ROOT_DIR', os.environ["EHIVE_ROOT_DIR"])] )
        return command

    def get_key(self):
        schema_file = self.arguments[0].replace('$EHIVE_ROOT_DIR', os.environ["EHIVE_ROOT_DIR"])
        with open(schema_file, "r") as fh:
            schema = fh.read()
        return (schema, tuple(sorted(self.options.items())))

    def get_cache(self):
        if os.path.exists(self.cache_filename):
            with open(self.cache_filename, "rb") as fh:
                return pickle.load(fh)
        return {}

    def write_cache(self, content_cache):
        with open(self.cache_filename, "wb") as fh:
            pickle.dump(content_cache, fh)

    def get_content(self):
        if 'cached' not in self.options:
            return super(SchemaDocumentation, self).get_content()
        key = self.get_key()
        content_cache = self.get_cache()
        if key in content_cache:
            return content_cache[key]
        content = super(SchemaDocumentation, self).get_content()
        content_cache[key] = content
        self.write_cache(content_cache)
        return content

class ScriptDocumentation(IncludeCommand):
    required_arguments = 1
    optional_arguments = 0
    final_argument_whitespace = False
    option_spec = {}

    def get_command(self):
        script_name = self.arguments[0]
        script_path = os.path.join(os.environ["EHIVE_ROOT_DIR"], "scripts", script_name+".pl")
        self.state.document.settings.record_dependencies.add(script_path)
        # If the command becomes too tricky, we can still decide to implement get_content() instead
        command = '''awk 'BEGIN{p=1} $0 ~ /^=head/ {if (($2 == "NAME") || ($2 == "LICENSE") || ($2 == "CONTACT")) {p=0} else {p=1}} p {print}' %s | pod2html --noindex --title=%s | pandoc --standalone --base-header-level=2 -f html -t rst | sed '/^--/ s/\\\//g' ''' % (script_path, script_name)
        return command


def cleanup_pod2html_tmp(app, exception):
    # Stolen from https://stackoverflow.com/questions/10840533/most-pythonic-way-to-delete-a-file-which-may-not-exist
    try:
        os.remove("pod2htmd.tmp")
    except OSError as e: # this would be "except OSError, e:" before Python 2.6
        if e.errno != errno.ENOENT: # errno.ENOENT = no such file or directory
            raise # re-raise exception if a different error occurred


def setup(app):
    app.add_directive('schema_documentation', SchemaDocumentation)
    app.add_directive('script_documentation', ScriptDocumentation)
    app.connect('build-finished', cleanup_pod2html_tmp)

