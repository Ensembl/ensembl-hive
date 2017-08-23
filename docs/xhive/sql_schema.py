
##############################################################
## Sphinx extension to colour the HTML schema documentation ##
##############################################################

from docutils import nodes

import sphinx.ext.graphviz


class SchemaDiagramDirective(sphinx.ext.graphviz.Graphviz):
    has_content = True
    required_arguments = 0
    optional_arguments = 1
    final_argument_whitespace = False
    option_spec = {}

    def run(self):
        nodes = super(SchemaDiagramDirective, self).run()
        for _ in nodes:
            _.__class__ = versatile_graphviz
        return nodes

class versatile_graphviz(sphinx.ext.graphviz.graphviz):
    pass


def html_visit_graphviz(self, node):
    code = node['code']
    # svg files are smaller than png
    format = 'svg'
    try:
        fname, outfn = sphinx.ext.graphviz.render_dot(self, code, node['options'], format, 'graphviz')
    except sphinx.ext.graphviz.GraphvizError as exc:
        self.builder.warn('dot code %r: ' % code + str(exc))
        raise nodes.SkipNode

    if fname is None:
        self.body.append(self.encode(code))
    # this svg handler does not make the images clickable
    #elif format == 'svg':
        #self.body.append('<a class="reference internal image-reference" href="{0}"><object data="{0}" type="image/svg+xml" class="align-center" style="max-width: 500px; max-height: 500px"><p class="warning">{0}</p></object>'.format(fname))
    else:
        self.body.append('<a class="reference internal image-reference" href="{0}"><img alt="{0}" class="align-center" src="{0}" style="max-width: 500px; max-height: 500px"></a>'.format(fname))
    raise nodes.SkipNode

def latex_visit_graphviz(self, node):
    code = node['code'].replace("{", "{\nsize=\"8,5\";", 1)
    sphinx.ext.graphviz.render_dot_latex(self, node, code, node['options'])

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
    app.add_directive('schema_diagram', SchemaDiagramDirective)
    app.add_node(versatile_graphviz,
            html=(html_visit_graphviz, None),
            latex=(latex_visit_graphviz, None),
            )
    # Register the role and the node, and their handlers
    app.add_role('schema_table_header', schema_table_header_role)
    app.add_node(schema_table_header,
        html = (visit_schema_table_header_html, depart_schema_table_header_html),
        latex = (visit_schema_table_header_latex, depart_schema_table_header_latex),
    )

