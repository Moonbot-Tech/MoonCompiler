from pathlib import Path
from struct import pack

def align(data):
    return data + b'\0' * (-len(data) % 4)

def identifier(value):
    return pack('<HH', 0xffff, value) if isinstance(value, int) else value.encode('utf-16le') + b'\0\0'

def record(kind, name, data):
    header = align(identifier(kind) + identifier(name)) + pack('<IHHII', 0, 0 if kind==0 else 0x1030, 0, 0, 0)
    return pack('<II', len(data), 8 + len(header)) + header + align(data)

def short(value):
    b = value.encode('ascii')
    return bytes([len(b)]) + b

def component(kind, values, inherited=False):
    data = b'TPF0' + (b'\xf1' if inherited else b'') + short(kind) + short('Probe')
    for name, value in values.items():
        data += short(name) + b'\x04' + pack('<i', value)
    return data + b'\0\0'

payload = b'SDK2410-resource\0\xff\x7f'
res = record(0, 0, b'')
res += record(10, 'TRESOURCEBASE', component('TResourceBase', {'Value': 42, 'Other': 10}))
res += record(10, 'TRESOURCEDERIVED', component('TResourceDerived', {'Value': 77}, True))
res += record(10, 'NAMED_COMPONENT', component('TResourceBase', {'Value': 81}))
res += record(10, 'TRESOURCEBASE_SECOND', component('TResourceBase', {'Value': 92}))
res += record(10, 'TRESOURCEBASE_FIRST', component('TResourceBase', {'Value': 91}))
res += record(10, 'NAMED_RESOURCE', payload)
res += record(10, 321, payload)
res += record('CUSTOMTYPE', 'NAMED_RESOURCE', payload)
res += record('CUSTOMTYPE', 322, payload)
target = Path(__file__).with_name('sdk2410_resources.res')
target.write_bytes(res)
print(target, len(res))
