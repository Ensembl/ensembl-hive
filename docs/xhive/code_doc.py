
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


import json
import os.path
import subprocess
import sys

from docutils import io, nodes, statemachine
from docutils.parsers.rst import Directive, directives

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
        except IOError, error:
            # Show the content
            raise self.severe(u'Problems with "%s" command:\n%s.' % ''.join(self.options['command']), ErrorString(error))
        include_lines = statemachine.string2lines(rawtext, 4, convert_whitespace=True)
        self.state_machine.insert_input(include_lines, 'CMD')
        return []

    def get_command(self):
        return self.options['command']

    def get_content(self):
        command = self.get_command()
        if isinstance(command, basestring):
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
            'sort_headers' : directives.flag,
            'sort_tables' : directives.flag,
            'intro' : directives.unchanged,
            'embed_diagrams' : directives.flag,
            }

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
        for flag in ['sort_headers', 'sort_tables', 'embed_diagrams']:
            if flag in self.options:
                command.extend( ['--' + flag] )
        if 'intro' in self.options:
            command.extend( ['--intro', self.options['intro'].replace('$EHIVE_ROOT_DIR', os.environ["EHIVE_ROOT_DIR"])] )
        return command

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


def setup(app):
    app.add_directive('schema_documentation', SchemaDocumentation)
    app.add_directive('script_documentation', ScriptDocumentation)

