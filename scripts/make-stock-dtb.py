#!/usr/bin/env python3
"""Genera el DTB base de ruby desde el boot_b stock, preservando __symbols__.

Añade pstore@48090000 y ruby-dtb-probe; valida que los 62 targets del dtbo
existan en el DTB resultante.
"""
import re, struct, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
import argparse
BOOT=ROOT/'device/backups/boot_b-stock.img'
OUT=ROOT/'dts/ruby-stock-base.dtb'
DTS=ROOT/'dts/ruby-stock-base.dts'
DTBO=ROOT/'dts/ruby-dtbo.dts'
ap=argparse.ArgumentParser()
ap.add_argument('--boot', default=str(BOOT))
ap.add_argument('--out', default=str(OUT))
ap.add_argument('--dts', default=str(DTS))
ap.add_argument('--dtbo', default=str(DTBO))
a=ap.parse_args()
BOOT=Path(a.boot); OUT=Path(a.out); DTS=Path(a.dts); DTBO=Path(a.dtbo)

def u32(b,o): return struct.unpack_from('<I',b,o)[0]
def u64(b,o): return struct.unpack_from('<Q',b,o)[0]

b=BOOT.read_bytes()
assert b[:8]==b'ANDROID!' and u32(b,40)==2, 'se espera boot header v2'
page=u32(b,36); align=lambda n:(n+page-1)//page*page
ks,rs,ss=u32(b,8),u32(b,16),u32(b,24)
rec=u32(b,1632); ds=u32(b,1648)
off=page+align(ks)+align(rs)+align(ss)+align(rec)
dtb=bytearray(b[off:off+ds])
tmp=ROOT/'dts/.stock-base.tmp.dtb'; tmp.write_bytes(dtb)

def has(node, prop):
    return subprocess.run(['fdtget',str(tmp),node,prop],capture_output=True).returncode==0

if not has('/reserved-memory/ruby-dtb-probe','reg'):
    subprocess.run(['fdtput','-c',str(tmp),'/reserved-memory/ruby-dtb-probe'],check=True)
    subprocess.run(['fdtput','-t','x',str(tmp),'/reserved-memory/ruby-dtb-probe','reg','0','0x48000000','0','0x1000'],check=True)
    subprocess.run(['fdtput','-t','x',str(tmp),'/reserved-memory/ruby-dtb-probe','no-map','1'],check=True)

OUT.write_bytes(tmp.read_bytes()); tmp.unlink()
d=subprocess.run(['dtc','-I','dtb','-O','dts',str(OUT)],capture_output=True,text=True).stdout
DTS.write_text(d)
targets=sorted(set(re.findall(r'target = <&([^>]+)>',DTBO.read_text()))) if DTBO.is_file() else []
block=re.search(r'__symbols__ \{(.*?)\n\t\};',d,re.S)
syms=set(re.findall(r'^\s*([A-Za-z0-9_]+) = "/',block.group(1),re.M)) if block else set()
missing=[t for t in targets if t not in syms]
print(f'{OUT} {OUT.stat().st_size} B; symbols={len(syms)} dtbo_targets={len(targets)} missing={len(missing)}')
if missing: print('missing:',missing)
