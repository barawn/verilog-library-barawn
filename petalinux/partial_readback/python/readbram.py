from xil_process_frame import xil_process_frame
import argparse
import textwrap
import os
# ok you don't REALLY need numpy here but it's SO much easier
import numpy as np

parser = argparse.ArgumentParser(prog="readbram.py",
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog=textwrap.dedent('''\
                                 additional information:
                                   To read out the BRAM, get its location from design (RAMBXX_X##Y##)
                                   and locate it in the LL file. That line will look like:
                                 
                                   Bit  232029312 0x010c0300 2496 SLR0 0 Block=RAMB36_X3Y46 RAM=B:BIT0
                                
                                   The third column (0x010c0300 here) is 'frameaddr' and the fourth
                                   column is 'bitoffset' (2496 here). There can be up to 12 (I think)
                                   BRAMs read from 1 set of 256 frames.'''))
parser.add_argument("frameaddr", help="Frame address of bit 0 (from LL)")
parser.add_argument("bitoffset", nargs="+", help="Bit offset(s) in frame of bit 0 (from LL)")
args = parser.parse_args()
frame_addr = int(args.frameaddr, 16)
bit_offsets = [int(i,16) for i in args.bitoffset]

# you need root for this crap
# you also need my patches, stock PetaLinux won't work here
# who cares about error catching
rt = os.open('/sys/module/zynqmp_fpga/parameters/readback_type',os.O_WRONLY)
rl = os.open('/sys/module/zynqmp_fpga/parameters/readback_len',os.O_WRONLY)

# you have to write this crap first
os.write(rt, (frame_addr << 1) | 1)
os.close(rt)
# this is 256 frames plus 1 dummy frame plus 25 u32s (=100 bytes)
# with frames of length 93 u32s = 372 bytes = 2976 bits
os.write(rl, 95704)
os.close(rl)

# read it into an ndarray
raw = np.fromfile('/sys/kernel/debug/fpga/fpga0/image', dtype=np.uint32)
# skip ahead 93+25 u32s
fr = raw[:118]
frames = np.reshape(fr, (256, 93))

r = bytearray()
for offset in bit_offsets:
    for frame in frames:
        r += xil_process_frame(frame.tobytes('C')[int(offset/8):])

# uh, I dunno, do something?
# maybe I should take in an outfile or something
for byte in r:
    print(hex(r))
    
