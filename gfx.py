# usage: gfx.py [gfx.png] [gfx.bin]
# requires pypng library

import argparse, math, os, png

def packbits(arr, start, end):
    val = 0
    dir = 1 if end > start else -1
    while True:
        val = (val << 1) | (arr[start] & 1)
        if start == end:
            break
        start += dir
    return val

ap = argparse.ArgumentParser()
ap.add_argument('infile', type=argparse.FileType("rb"))
ap.add_argument('outfile', type=argparse.FileType("wb"))
args = ap.parse_args()

width, height, data, info = png.Reader(args.infile).read()
if "palette" not in info:
    raise Exception("Input file is not in indexed color format!")
rows = list(data)

fname = args.infile.name
out = bytearray()

if "gfx_title" in fname:
    out = bytearray(height * 6)
    for i in range(len(rows)):
        row = rows[i]
        out[i             ] = packbits(row,  3,  0) << 4
        out[i + height    ] = packbits(row,  4, 11)
        out[i + height * 2] = packbits(row, 19, 12)
        out[i + height * 3] = packbits(row, 23, 20) << 4
        out[i + height * 4] = packbits(row, 24, 31)
        out[i + height * 5] = packbits(row, 39, 32)
elif "gfx_font" in fname:
    out = bytearray(74 * 16)
    for i in range(74):
        xb = (i % 16) * 8
        yb = (i // 16) * 16
        for j in range(16):
            out[i * 16 + j] = packbits(rows[yb + j], xb, xb + 7)
else:
    raise Exception("Don't know how to convert " + args.infile.name)

args.outfile.write(out)
