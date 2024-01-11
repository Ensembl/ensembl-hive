
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

import json
import os.path

from docutils import nodes


hive_colours = {}

class hivestatus(nodes.Element):
    pass

def hivestatus_role(name, rawtext, text, lineno, inliner, options={}, content=[]):
    status = text[1:text.index('>')]
    text = (text[text.index('>')+1:]).strip()
    hivestatus_node = hivestatus()
    hivestatus_node.append(nodes.Text(text))
    hivestatus_node['status'] = status

    return [hivestatus_node], []

def visit_hivestatus_html(self, node):
    load_colours_if_needed()
    self.body.append('<span style="background-color:%s">' % hive_colours[node['status']])

def depart_hivestatus_html(self, node):
    self.body.append('</span>')

def visit_hivestatus_latex(self, node):
    load_colours_if_needed()
    self.body.append('\n\\colorbox{%s}{' % hive_colours[node['status']])

def depart_hivestatus_latex(self, node):
    self.body.append('}')

def load_colours_if_needed():
    # eHive's default configuration file
    default_config_file = os.environ["EHIVE_ROOT_DIR"] + os.path.sep + "hive_config.json"
    with open(default_config_file, "r") as fc:
        conf_content = json.load(fc)
        as_hash = conf_content["Graph"]["Node"]["AnalysisStatus"]
        for s in as_hash:
            if isinstance(as_hash[s], dict):
                hive_colours[s] = as_hash[s]["Colour"]
        js_hash = conf_content["Graph"]["Node"]["JobStatus"]
        for s in js_hash:
            if isinstance(js_hash[s], dict):
                hive_colours[s] = js_hash[s]["Colour"]

## Register the extension
def setup(app):
    app.add_role('hivestatus', hivestatus_role)
    app.add_node(hivestatus,
        html = (visit_hivestatus_html, depart_hivestatus_html),
        latex = (visit_hivestatus_latex, depart_hivestatus_latex),
    )

