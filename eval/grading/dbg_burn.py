import sys
sys.path.insert(0, '/home/melezaly/Projects/Rescate/eval')
from rag_mirror.triage import triage

q = "my hand is burned and looks bad but doesnt hurt"
print("tokens:", q.split())
print("triage:", triage(q))
q2 = "i burned my hand"
print("q2 triage:", triage(q2))
