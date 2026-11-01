#!/usr/bin/env python3
"""Isolated x86 decoder oracle. Requires Unicorn 2.1.4 in a separate environment.
Maps the user's DLL as data; executes only the known Oodle-0 leaf entry.
No DllMain, Windows, imports, filesystem, network or client code is run by guest.
Allocator/free callbacks are emulated in a bounded private guest heap.
"""
import argparse, hashlib, json, struct
from pathlib import Path
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE, UcError
from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX

DLL_SHA = 'befa33fb43f03c6d0b9cbb302bfd7eb7efa2ba8ec682f75f63ac5cd03653570d'
def u32(b, p): return struct.unpack_from('<I', b, p)[0]
def pack(*values): return struct.pack('<' + 'I'*len(values), *values)
def digest(b): return hashlib.sha256(b).hexdigest()

def decode(dll, compressed, stop0, stop1, size):
    if digest(dll) != DLL_SHA: raise ValueError('This oracle is specific to the verified 2002 RO DLL digest')
    if not 0 < size <= 64*1024*1024: raise ValueError('Output size outside oracle limit')
    pe = u32(dll, 0x3c); opt = pe + 24
    base = u32(dll, opt + 28); image_size = u32(dll, opt + 56)
    uc = Uc(UC_ARCH_X86, UC_MODE_32)
    uc.mem_map(base, (image_size+4095)&~4095)
    uc.mem_write(base, dll[:u32(dll, opt+60)])
    sections = pe + 24 + struct.unpack_from('<H', dll, pe+20)[0]
    for i in range(struct.unpack_from('<H', dll, pe+6)[0]):
        p = sections + i*40
        virtual, raw_size, raw = u32(dll,p+12), u32(dll,p+16), u32(dll,p+20)
        if raw_size: uc.mem_write(base+virtual,dll[raw:raw+raw_size])
    STACK, INPUT, OUTPUT, HEAP, STUB = 0x01000000,0x02000000,0x08000000,0x18000000,0x20000000
    uc.mem_map(STACK, 1024*1024)
    uc.mem_map(INPUT, (len(compressed)+64+4095)&~4095)
    uc.mem_write(INPUT, compressed + bytes(32))
    uc.mem_map(OUTPUT, (size+4095)&~4095)
    uc.mem_map(HEAP, 16*1024*1024)
    uc.mem_map(STUB,4096);uc.mem_write(STUB,b'\xc3'*64)
    ALLOC, FREE, RETURN = STUB,STUB+16,STUB+32
    uc.mem_write(0x10033620,pack(ALLOC));uc.mem_write(0x10033624,pack(FREE))
    allocated=0
    def stub(machine,address,size_,userdata):
        nonlocal allocated
        esp=machine.reg_read(UC_X86_REG_ESP)
        if address==ALLOC:
            args=struct.unpack('<5I',machine.mem_read(esp,20))
            alignment, n=args[3],args[4]
            alignment=max(4,alignment)
            if alignment>4096 or alignment&(alignment-1): raise ValueError('Invalid allocation alignment')
            offset=(allocated+alignment-1)&~(alignment-1)
            if n>16*1024*1024-offset: raise ValueError('Oracle heap exhausted')
            allocated=offset+n
            machine.reg_write(UC_X86_REG_EAX,HEAP+offset)
        elif address==FREE: machine.reg_write(UC_X86_REG_EAX,0)
        elif address==RETURN: machine.emu_stop()
    uc.hook_add(UC_HOOK_CODE,stub,begin=STUB,end=STUB+63)
    esp=STACK+1024*1024-128
    uc.mem_write(esp,pack(RETURN,len(compressed),INPUT,stop0,stop1,size,OUTPUT))
    uc.reg_write(UC_X86_REG_ESP,esp)
    try: uc.emu_start(0x1001d060,RETURN,timeout=10_000_000,count=200_000_000)
    except UcError as exc: raise RuntimeError(f'Decoder stopped at {uc.reg_read(UC_X86_REG_EIP):#x}: {exc}') from exc
    if uc.reg_read(UC_X86_REG_EIP)!=RETURN: raise RuntimeError('Oracle timed out or exceeded instruction budget')
    return bytes(uc.mem_read(OUTPUT,size))

def main():
    a=argparse.ArgumentParser();a.add_argument('dll',type=Path);a.add_argument('corpus',type=Path);a.add_argument('destination',type=Path);args=a.parse_args()
    dll=args.dll.read_bytes();args.destination.mkdir(parents=True,exist_ok=True)
    records=[]
    for path in sorted(args.corpus.glob('*.gr2')):
        b=path.read_bytes();start=32+u32(b,44)
        for i in range(u32(b,48)):
            p=start+44*i;mode,offset,stored,expanded,align,stop0,stop1=struct.unpack_from('<7I',b,p)
            if not expanded: continue
            if mode==0: out=b[offset:offset+stored]
            elif mode==1: out=decode(dll,b[offset:offset+stored],stop0,stop1,expanded)
            else: raise ValueError(f'Unsupported mode {mode}')
            name=f'{path.stem}-{i}.bin';(args.destination/name).write_bytes(out)
            records.append({'file':path.name,'fileSHA256':digest(b),'section':i,'compression':mode,'size':len(out),'sha256':digest(out),'output':name})
        print(path.name,'OK',flush=True)
    report={'dllSHA256':digest(dll),'oracle':'Unicorn isolated sub_1001d060, allocator/free stubs, no DLL initialization','sections':records}
    (args.destination/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
