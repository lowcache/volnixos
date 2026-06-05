import random
from auditor.generate import AccessControlGenerator

gen = AccessControlGenerator()
ch = gen.sample(random.Random(1337), "vulnerable")
print("Target src:")
print(ch.contract_src)
print("Combined src:")
print(ch.combined_src)
