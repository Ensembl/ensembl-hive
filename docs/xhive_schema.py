
##############################################################
## Sphinx extension to colour the HTML schema documentation ##
##############################################################

from docutils import nodes


## A node to record in the doctree
class schema_table_header(nodes.Element):
    pass


## The role, which will create an instance of the above node class
## Use like this
##   :schema_table_header:`<#C70C09,square>Pipeline structure`
def schema_table_header_role(name, rawtext, text, lineno, inliner, options={}, content=[]):
    (params,_,text) = text.partition('>')
    # "square" is the default shape
    if "," not in params:
        params = params + ",square"
    (colour_spec, shape) = params[1:].split(",")
    schema_table_header_node = schema_table_header()
    schema_table_header_node.children.append(nodes.Text(text))
    schema_table_header_node['colour_spec'] = colour_spec
    schema_table_header_node['shape'] = shape

    return [schema_table_header_node], []


## HTML writer
#
# <div> and <span> element with the right CSS class
#

def visit_schema_table_header_html(self, node):
    self.body.append('<div class="sql_schema_table_%s_bullet" style="border-color:%s;"><span style="background-color:%s;"></span>' % (node['shape'], node['colour_spec'], node['colour_spec']))

def depart_schema_table_header_html(self, node):
    self.body.append('</div>')


## Latex writer
#
# Don't do anything, i.e. no colour
#

def visit_schema_table_header_latex(self, node):
    pass

def depart_schema_table_header_latex(self, node):
    pass


## Register the extension
def setup(app):
    # Add the CSS
    app.add_stylesheet("schema_doc.css")
    # Register the role and the node, and their handlers
    app.add_role('schema_table_header', schema_table_header_role)
    app.add_node(schema_table_header,
        html = (visit_schema_table_header_html, depart_schema_table_header_html),
        latex = (visit_schema_table_header_latex, depart_schema_table_header_latex),
    )

