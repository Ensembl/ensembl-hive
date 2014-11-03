
import sys
import numbers
import warnings
import collections

class ParamWarning(Warning):
    pass
class ParamException(Exception):
    pass
class ParamInfiniteLoopException(ParamException):
    def __init__(self, inside_hashes, _substitution_in_progress):
        ParamException.__init__(self, "Substitution loop has been detected on {0}. Parameter-substitution stack: {1}".format(inside_hashes, list(_substitution_in_progress.keys())))

class Param(object):

    # Constructor
    #############
    def __init__(self, u):
        self._unsubstituted_param_hash = u
        self._param_hash = {}

    # Public methods
    #################
    def set_param(self, param_name, value):
        self._validate_parameter_name(param_name)
        self._param_hash[param_name] = value
        return value

    def get_param(self, param_name):
        self._substitution_in_progress = collections.OrderedDict()
        return self._internal_get_param(param_name)

    def has_param(self, param_name):
        self._validate_parameter_name(param_name)
        return (param_name in self._param_hash) or (param_name in self._unsubstituted_param_hash)

    # Private methods
    ##################
    def _validate_parameter_name(self, param_name):
        if (param_name is None) or not isinstance(param_name, str) or (param_name == ''):
            raise NameError("'{0}' (of type {1}) is not a valid parameter name".format(param_name, type(param_name)))

    def _internal_get_param(self, param_name):
        self._validate_parameter_name(param_name)
        if param_name not in self._param_hash:
            x = self._unsubstituted_param_hash[param_name]
            self._param_hash[param_name] = self._param_substitute(x)
        return self._param_hash[param_name]

    def _param_substitute(self, structure):

        if structure is None:
            return None

        elif isinstance(structure, list):
            return [self._param_substitute(_) for _ in structure]

        elif isinstance(structure, dict):
            return {self._param_substitute(key): self._param_substitute(value) for (key,value) in structure.items()}

        elif isinstance(structure, numbers.Number):
            return structure

        elif isinstance(structure, str):

            # We handle the substitution differently if there is a single reference as we can avoid forcing the result to be a string
            if structure.startswith('#expr(') and structure.endswith(')expr#'):
                return self._subst_one_hashpair(structure[1:-1])

            # TODO need n_hashes ?
            n_hashes = structure.count('#')
            if n_hashes % 2:
                # TODO warning message
                raise SyntaxError("ParamError: Odd number of '#' in the parameter '{0}'. Cannot substitute the parameters".format(structure))

            if structure.startswith('#') and structure.endswith('#') and len(structure) >= 3 and n_hashes == 2:
                return self._subst_one_hashpair(structure[1:-1])

            return self._parse_hash_blocks(structure, lambda middle_param: self._subst_one_hashpair(middle_param) )

        else:
            # TODO warning message
            raise SystemExit("ParamError: Cannot substitute parameters on a '{0}'".format(type(structure)))


    # TODO need a different way of doing that
    def _parse_hash_blocks(self, structure, callback):
            result = []
            while '#' in structure:
                (head,_,tmp) = structure.partition('#')
                result.append(head)
                if tmp.startswith('expr('):
                    i = tmp.find(')expr#')
                    val = callback(tmp[:i+5])
                    tail = tmp[i+6:]
                else:
                    (middle_param,_,tail) = tmp.partition('#')
                    if middle_param == '':
                        val = '##'
                    else:
                        val = callback(middle_param)
                if val is None:
                    return None
                result.append(str(val))
                structure = tail
            return ''.join(result) + structure



    def _subst_one_hashpair(self, inside_hashes):
        print('_subst_one_hashpair', inside_hashes)

        if inside_hashes in self._substitution_in_progress:
            raise ParamInfiniteLoopException(inside_hashes, self._substitution_in_progress)
        self._substitution_in_progress[inside_hashes] = 1

        if inside_hashes.startswith('expr(') and inside_hashes.endswith(')expr'):
            expression = inside_hashes[5:-5].strip()
            #print(">>> Going to eval: " + expression)
            val = self._parse_hash_blocks(expression, lambda middle_param: self._internal_get_param(middle_param))
            #print("=== " + val)
            val = eval(val)

        elif ':' in inside_hashes:
            (func_name,_,parameters) = inside_hashes.partition(':')
            if func_name in globals():
                val = globals()[func_name](self._internal_get_param(parameters))
            else:
                raise SyntaxError("Unknown method: " + func_name)
        else:
            val = self._internal_get_param(inside_hashes)

        if val is None:
            warnings.warn("Substituting an undefined value of #{0}#".format(inside_hashes), ParamWarning)

        del self._substitution_in_progress[inside_hashes]
        return val



if __name__ == '__main__':

    seed_params = {
        'alpha' : 2,
        'beta' : 5,
        'delta' : '#expr( #alpha#*#beta# )expr#',

        'gamma' : [10,20,33,15],
        'gamma_prime' : '#expr( list(#gamma#) )expr#',

        'age' : { 'Alice' : 17, 'Bob' : 20, 'Chloe' : 21},
        'age_prime' : '#expr( dict(#age#) )expr#',

        'csv' : '[123,456,789]',
        'listref' : '#expr( #csv# )expr#'
    }

    p = Param(seed_params)

    print('All the parameters')
    for (key,value) in seed_params.items():
        print("\t'{0}' is '{1}' in the seeded hash, and '{2}' as a result of p.param()".format(key, value, p.get_param(key)))

    print("Numbers")
    print(p._param_substitute( "\tSubstituting one scalar: #alpha# and another: #beta# and again one: #alpha# and the other: #beta# . Their product: #delta#" ));

    print("Lists")
    print(p._param_substitute( "\tdefault stringification of gamma: #gamma#" ));
    print(p._param_substitute( "\texpr-stringification gamma: #expr( #gamma#  )expr#" ));
    print(p._param_substitute( "\tcomplex join of gamma: #expr( '~'.join([str(_) for _ in sorted(#gamma#)])  )expr#" ));
    print(p._param_substitute( "\tcomplex join of gamma_prime: #expr( '~'.join([str(_) for _ in sorted(#gamma_prime#)])  )expr#" ));

    print("Global methods")
    print(p._param_substitute( "\tsum(gamma) -> #expr( sum(#gamma#) )expr#" ));
    print(p._param_substitute( "\tmin(gamma) -> #expr( min(#gamma#) )expr#" ));
    print(p._param_substitute( "\tmax(gamma) -> #expr( max(#gamma#) )expr#" ));

    print("Dictionaries")
    print(p._param_substitute( '\tdefault stringification of age: #age#'))
    print(p._param_substitute( '\texpr-stringification of age: #expr( #age# )expr#'))
    print(p._param_substitute( '\tcomplex fold of age: #expr( "\t".join(["{0} is {1} years old".format(p,a) for (p,a) in #age#.items()]) )expr#'));
    print(p._param_substitute( '\tcomplex fold of age_prime: #expr( "\t".join(["{0} is {1} years old".format(p,a) for (p,a) in #age_prime#.items()]) )expr#'));

    print("With indexes")
    print(p._param_substitute( '\tadding indexed values: #expr( #age#["Alice"]+max(#gamma#)+#listref#[0] )expr#'));

    print("Evaluation")
    print("\tcsv =", p.get_param('csv'), "(it is a {0}".format(type(p.get_param('csv'))), ')')
    l = p._param_substitute( '#listref#' )
    print("\tlist reference produced by doing expr() on csv: ", l)
    p.get_param(0)


