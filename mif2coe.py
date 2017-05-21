import sys
print('memory_initialization_radix = 16;')
vector = []
vector.append('memory_initialization_vector = ')
with open(sys.argv[1], 'r') as f:
    for l in f:
        vector.append(l.strip())
        vector.append(',')
vector.pop()
vector.append(';')
print(''.join(vector))