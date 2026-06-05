from auditor.verify import verify
import random
from auditor.generate import AccessControlGenerator

gen = AccessControlGenerator()
ch = gen.sample(random.Random(1337), "vulnerable")
v = verify(ch.combined_src)
print("Verdict:", v)
print("Detail:", v.detail)
