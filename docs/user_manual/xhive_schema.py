
from docutils import nodes

__all__ = [ "schema_table_header", "schema_table_header_role", "visit_schema_table_header_html", "depart_schema_table_header_html", "visit_schema_table_header_latex", "depart_schema_table_header_latex"]


class schema_table_header(nodes.Element):
    pass

def schema_table_header_role(name, rawtext, text, lineno, inliner, options={}, content=[]):
    (params,_,text) = text.partition('>')
    if "," not in params:
        params = params + ",square"
    (colour_spec, shape) = params[1:].split(",")
    schema_table_header_node = schema_table_header()
    schema_table_header_node.children.append(nodes.Text(text))
    schema_table_header_node['colour_spec'] = colour_spec
    schema_table_header_node['shape'] = shape

    return [schema_table_header_node], []

def visit_schema_table_header_html(self, node):
    self.body.append('<div class="sql_schema_table_%s_bullet" style="border-color:%s;"><span style="background-color:%s;"></span>' % (node['shape'], node['colour_spec'], node['colour_spec']))

def depart_schema_table_header_html(self, node):
    self.body.append('</div>')

def visit_schema_table_header_latex(self, node):
    pass

def depart_schema_table_header_latex(self, node):
    pass


