
import eHive

import time

class AddTogether(eHive.BaseRunnable):
    """Runnable that adds up all the partial-multiplications from PartMultiply"""

    def param_defaults(self):
        return {
            'take_time' : 0,
            'partial_product' : {}
        }


    def fetch_input(self):
        a_multiplier = self.param_required('a_multiplier')
        partial_product = self.param('partial_product')
        print(partial_product)

        partial_product['1'] = str(a_multiplier)
        partial_product['0'] = '0'


    def run(self):
        b_multiplier = self.param_required('b_multiplier')
        partial_product = self.param('partial_product')
        self.param('result', _add_together(b_multiplier, partial_product))
        time.sleep( self.param('take_time') )

    def write_output(self):
        self.dataflow( { 'result': self.param('result') }, 1)



def _add_together(b_multiplier, partial_product):

    b_multiplier = str(b_multiplier)
    accu = [0] * (1 + len(b_multiplier) + len(partial_product['1']))

    for (i,b_digit) in enumerate(reversed(b_multiplier)):
        product = str(partial_product[b_digit])
        for (j,p_digit) in enumerate(reversed(product)):
            accu[i+j] += int(p_digit)

    carry = 0
    for i in range(len(accu)):
        val = carry + accu[i]
        accu[i] = val % 10
        carry = val // 10

    return ''.join(str(_) for _ in reversed(accu)).lstrip('0')

1;
