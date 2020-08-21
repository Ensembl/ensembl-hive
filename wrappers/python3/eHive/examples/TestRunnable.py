
import eHive

class TestRunnable(eHive.BaseRunnable):
    """Simple Runnable to test as a standaloneJob"""

    def param_defaults(self):
        return {
            'alpha' : 37,
            'beta' : 78,
            'gamma' : '#alpha#',
            'delta' : 'one#hash',
        }

    def fetch_input(self):
        self.warning("Fetch the world !")
        print("alpha is", self.param_required('alpha'))
        print("beta is", self.param_required('beta'))
        print("gamma is", self.param_required('gamma'))
        print("delta is", self.param_required('delta'))

    def run(self):
        self.warning("Run the world !")
        s = self.param('alpha') + self.param('beta')
        print("set gamma to", s)
        self.param('gamma', s)

    def write_output(self):
        self.warning("Write to the world !")
        print("gamma is", self.param('gamma'))
        self.dataflow( {'gamma': self.param('gamma')}, 2 )

