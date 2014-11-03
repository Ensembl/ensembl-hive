
import sys

print(sys.argv, file=sys.stderr)

module_name = sys.argv[1]
module = __import__(module_name)

runnable = getattr(module, module_name)(int(sys.argv[2]), int(sys.argv[3]))

runnable.life_cycle()

