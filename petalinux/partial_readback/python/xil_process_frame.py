# This horrible-ness is how you extract the 128 BRAM bits
# contained in a 2976 bit (93x32) frame in a Xilinx UltraScale+
# device.
#
# The mappings (mostly) do not change, ever, for any block RAM:
# each BRAM *individually* has a 'start offset' corresponding
# to its place in the Y column, and each X column has an offset
# as well.
#
# But once that offset's taken care of, everything maps out
# exactly. The 'start offset' and FAR can be obtained from
# the .ll file: the frame address is column 3, and the start
# offset is column 4 for the RAM=B:BIT0 entry.
#
# The start offsets are:
# 0   = 0
# 240 = 30
# 480 = 60
# 720 = 90
# 960 = 120
# 1200 = 150

# 1536
# 1776
# 2016
# 2256
# 2496
# 2736
#
# who knows what the extra 96 bytes in the middle are for
#
# Note that while these offsets are all on byte boundaries,
# they are NOT all on uint32 boundaries. So you pass a byte
# stream here.
# 
# Each RAMB36 consists of 256 total frames.
# So to read out a block RAM, you just set the FAR register
# to its starting frame address (from the LL file),
# read 23,808 32-bit integers (or 95,232 bytes),
# slice them up by frame, and call this.
#
# To do this with the hacked-up modified readback,
# you need to increase the read length because of
# God Knows What The Hell.
#
# Trial-and-error says there's a 472-byte offset, so you need
# to read 95,704 bytes.
#
# You can then just read in from numpy:
# bramOffset = 240
# raw = np.fromfile("bram_dump", dtype=np.uint32)
# fr = raw[118:]
# frames = np.reshape(fr, (256, 93))
# r = bytearray()
# for frame in frames:
#     r += xil_process_frame(frame.tobytes('C')[bramOffset/8:])
#
# NOTE NOTE NOTE: the idiotic "-30" here is because
# I built this with a BRAM with bramOffset = 240
# Note that this ALSO means you're best off packing up 12
# BRAMs-ish at a time since you get them all anyway.
# 
def xil_process_frame(f):
    r = bytearray(16)
    r[ 0 ] |= ((f[ 30 - 30 ] >>  0 )&0x1) <<  0
    r[ 0 ] |= ((f[ 46 - 30 ] >>  4 )&0x1) <<  1
    r[ 0 ] |= ((f[ 31 - 30 ] >>  4 )&0x1) <<  2
    r[ 0 ] |= ((f[ 48 - 30 ] >>  0 )&0x1) <<  3
    r[ 0 ] |= ((f[ 33 - 30 ] >>  0 )&0x1) <<  4
    r[ 0 ] |= ((f[ 49 - 30 ] >>  4 )&0x1) <<  5
    r[ 0 ] |= ((f[ 34 - 30 ] >>  4 )&0x1) <<  6
    r[ 0 ] |= ((f[ 51 - 30 ] >>  0 )&0x1) <<  7
    r[ 1 ] |= ((f[ 37 - 30 ] >>  4 )&0x1) <<  0
    r[ 1 ] |= ((f[ 54 - 30 ] >>  0 )&0x1) <<  1
    r[ 1 ] |= ((f[ 39 - 30 ] >>  0 )&0x1) <<  2
    r[ 1 ] |= ((f[ 55 - 30 ] >>  4 )&0x1) <<  3
    r[ 1 ] |= ((f[ 40 - 30 ] >>  4 )&0x1) <<  4
    r[ 1 ] |= ((f[ 57 - 30 ] >>  0 )&0x1) <<  5
    r[ 1 ] |= ((f[ 42 - 30 ] >>  0 )&0x1) <<  6
    r[ 1 ] |= ((f[ 58 - 30 ] >>  4 )&0x1) <<  7
    r[ 2 ] |= ((f[ 30 - 30 ] >>  6 )&0x1) <<  0
    r[ 2 ] |= ((f[ 47 - 30 ] >>  2 )&0x1) <<  1
    r[ 2 ] |= ((f[ 32 - 30 ] >>  2 )&0x1) <<  2
    r[ 2 ] |= ((f[ 48 - 30 ] >>  6 )&0x1) <<  3
    r[ 2 ] |= ((f[ 33 - 30 ] >>  6 )&0x1) <<  4
    r[ 2 ] |= ((f[ 50 - 30 ] >>  2 )&0x1) <<  5
    r[ 2 ] |= ((f[ 35 - 30 ] >>  2 )&0x1) <<  6
    r[ 2 ] |= ((f[ 51 - 30 ] >>  6 )&0x1) <<  7
    r[ 3 ] |= ((f[ 38 - 30 ] >>  2 )&0x1) <<  0
    r[ 3 ] |= ((f[ 54 - 30 ] >>  6 )&0x1) <<  1
    r[ 3 ] |= ((f[ 39 - 30 ] >>  6 )&0x1) <<  2
    r[ 3 ] |= ((f[ 56 - 30 ] >>  2 )&0x1) <<  3
    r[ 3 ] |= ((f[ 41 - 30 ] >>  2 )&0x1) <<  4
    r[ 3 ] |= ((f[ 57 - 30 ] >>  6 )&0x1) <<  5
    r[ 3 ] |= ((f[ 42 - 30 ] >>  6 )&0x1) <<  6
    r[ 3 ] |= ((f[ 59 - 30 ] >>  2 )&0x1) <<  7
    r[ 4 ] |= ((f[ 30 - 30 ] >>  3 )&0x1) <<  0
    r[ 4 ] |= ((f[ 46 - 30 ] >>  7 )&0x1) <<  1
    r[ 4 ] |= ((f[ 31 - 30 ] >>  7 )&0x1) <<  2
    r[ 4 ] |= ((f[ 48 - 30 ] >>  3 )&0x1) <<  3
    r[ 4 ] |= ((f[ 33 - 30 ] >>  3 )&0x1) <<  4
    r[ 4 ] |= ((f[ 49 - 30 ] >>  7 )&0x1) <<  5
    r[ 4 ] |= ((f[ 34 - 30 ] >>  7 )&0x1) <<  6
    r[ 4 ] |= ((f[ 51 - 30 ] >>  3 )&0x1) <<  7
    r[ 5 ] |= ((f[ 37 - 30 ] >>  7 )&0x1) <<  0
    r[ 5 ] |= ((f[ 54 - 30 ] >>  3 )&0x1) <<  1
    r[ 5 ] |= ((f[ 39 - 30 ] >>  3 )&0x1) <<  2
    r[ 5 ] |= ((f[ 55 - 30 ] >>  7 )&0x1) <<  3
    r[ 5 ] |= ((f[ 40 - 30 ] >>  7 )&0x1) <<  4
    r[ 5 ] |= ((f[ 57 - 30 ] >>  3 )&0x1) <<  5
    r[ 5 ] |= ((f[ 42 - 30 ] >>  3 )&0x1) <<  6
    r[ 5 ] |= ((f[ 58 - 30 ] >>  7 )&0x1) <<  7
    r[ 6 ] |= ((f[ 31 - 30 ] >>  1 )&0x1) <<  0
    r[ 6 ] |= ((f[ 47 - 30 ] >>  5 )&0x1) <<  1
    r[ 6 ] |= ((f[ 32 - 30 ] >>  5 )&0x1) <<  2
    r[ 6 ] |= ((f[ 49 - 30 ] >>  1 )&0x1) <<  3
    r[ 6 ] |= ((f[ 34 - 30 ] >>  1 )&0x1) <<  4
    r[ 6 ] |= ((f[ 50 - 30 ] >>  5 )&0x1) <<  5
    r[ 6 ] |= ((f[ 35 - 30 ] >>  5 )&0x1) <<  6
    r[ 6 ] |= ((f[ 52 - 30 ] >>  1 )&0x1) <<  7
    r[ 7 ] |= ((f[ 38 - 30 ] >>  5 )&0x1) <<  0
    r[ 7 ] |= ((f[ 55 - 30 ] >>  1 )&0x1) <<  1
    r[ 7 ] |= ((f[ 40 - 30 ] >>  1 )&0x1) <<  2
    r[ 7 ] |= ((f[ 56 - 30 ] >>  5 )&0x1) <<  3
    r[ 7 ] |= ((f[ 41 - 30 ] >>  5 )&0x1) <<  4
    r[ 7 ] |= ((f[ 58 - 30 ] >>  1 )&0x1) <<  5
    r[ 7 ] |= ((f[ 43 - 30 ] >>  1 )&0x1) <<  6
    r[ 7 ] |= ((f[ 59 - 30 ] >>  5 )&0x1) <<  7
    r[ 8 ] |= ((f[ 30 - 30 ] >>  2 )&0x1) <<  0
    r[ 8 ] |= ((f[ 46 - 30 ] >>  6 )&0x1) <<  1
    r[ 8 ] |= ((f[ 31 - 30 ] >>  6 )&0x1) <<  2
    r[ 8 ] |= ((f[ 48 - 30 ] >>  2 )&0x1) <<  3
    r[ 8 ] |= ((f[ 33 - 30 ] >>  2 )&0x1) <<  4
    r[ 8 ] |= ((f[ 49 - 30 ] >>  6 )&0x1) <<  5
    r[ 8 ] |= ((f[ 34 - 30 ] >>  6 )&0x1) <<  6
    r[ 8 ] |= ((f[ 51 - 30 ] >>  2 )&0x1) <<  7
    r[ 9 ] |= ((f[ 37 - 30 ] >>  6 )&0x1) <<  0
    r[ 9 ] |= ((f[ 54 - 30 ] >>  2 )&0x1) <<  1
    r[ 9 ] |= ((f[ 39 - 30 ] >>  2 )&0x1) <<  2
    r[ 9 ] |= ((f[ 55 - 30 ] >>  6 )&0x1) <<  3
    r[ 9 ] |= ((f[ 40 - 30 ] >>  6 )&0x1) <<  4
    r[ 9 ] |= ((f[ 57 - 30 ] >>  2 )&0x1) <<  5
    r[ 9 ] |= ((f[ 42 - 30 ] >>  2 )&0x1) <<  6
    r[ 9 ] |= ((f[ 58 - 30 ] >>  6 )&0x1) <<  7
    r[ 10 ] |= ((f[ 31 - 30 ] >>  0 )&0x1) <<  0
    r[ 10 ] |= ((f[ 47 - 30 ] >>  4 )&0x1) <<  1
    r[ 10 ] |= ((f[ 32 - 30 ] >>  4 )&0x1) <<  2
    r[ 10 ] |= ((f[ 49 - 30 ] >>  0 )&0x1) <<  3
    r[ 10 ] |= ((f[ 34 - 30 ] >>  0 )&0x1) <<  4
    r[ 10 ] |= ((f[ 50 - 30 ] >>  4 )&0x1) <<  5
    r[ 10 ] |= ((f[ 35 - 30 ] >>  4 )&0x1) <<  6
    r[ 10 ] |= ((f[ 52 - 30 ] >>  0 )&0x1) <<  7
    r[ 11 ] |= ((f[ 38 - 30 ] >>  4 )&0x1) <<  0
    r[ 11 ] |= ((f[ 55 - 30 ] >>  0 )&0x1) <<  1
    r[ 11 ] |= ((f[ 40 - 30 ] >>  0 )&0x1) <<  2
    r[ 11 ] |= ((f[ 56 - 30 ] >>  4 )&0x1) <<  3
    r[ 11 ] |= ((f[ 41 - 30 ] >>  4 )&0x1) <<  4
    r[ 11 ] |= ((f[ 58 - 30 ] >>  0 )&0x1) <<  5
    r[ 11 ] |= ((f[ 43 - 30 ] >>  0 )&0x1) <<  6
    r[ 11 ] |= ((f[ 59 - 30 ] >>  4 )&0x1) <<  7
    r[ 12 ] |= ((f[ 30 - 30 ] >>  5 )&0x1) <<  0
    r[ 12 ] |= ((f[ 47 - 30 ] >>  1 )&0x1) <<  1
    r[ 12 ] |= ((f[ 32 - 30 ] >>  1 )&0x1) <<  2
    r[ 12 ] |= ((f[ 48 - 30 ] >>  5 )&0x1) <<  3
    r[ 12 ] |= ((f[ 33 - 30 ] >>  5 )&0x1) <<  4
    r[ 12 ] |= ((f[ 50 - 30 ] >>  1 )&0x1) <<  5
    r[ 12 ] |= ((f[ 35 - 30 ] >>  1 )&0x1) <<  6
    r[ 12 ] |= ((f[ 51 - 30 ] >>  5 )&0x1) <<  7
    r[ 13 ] |= ((f[ 38 - 30 ] >>  1 )&0x1) <<  0
    r[ 13 ] |= ((f[ 54 - 30 ] >>  5 )&0x1) <<  1
    r[ 13 ] |= ((f[ 39 - 30 ] >>  5 )&0x1) <<  2
    r[ 13 ] |= ((f[ 56 - 30 ] >>  1 )&0x1) <<  3
    r[ 13 ] |= ((f[ 41 - 30 ] >>  1 )&0x1) <<  4
    r[ 13 ] |= ((f[ 57 - 30 ] >>  5 )&0x1) <<  5
    r[ 13 ] |= ((f[ 42 - 30 ] >>  5 )&0x1) <<  6
    r[ 13 ] |= ((f[ 59 - 30 ] >>  1 )&0x1) <<  7
    r[ 14 ] |= ((f[ 31 - 30 ] >>  3 )&0x1) <<  0
    r[ 14 ] |= ((f[ 47 - 30 ] >>  7 )&0x1) <<  1
    r[ 14 ] |= ((f[ 32 - 30 ] >>  7 )&0x1) <<  2
    r[ 14 ] |= ((f[ 49 - 30 ] >>  3 )&0x1) <<  3
    r[ 14 ] |= ((f[ 34 - 30 ] >>  3 )&0x1) <<  4
    r[ 14 ] |= ((f[ 50 - 30 ] >>  7 )&0x1) <<  5
    r[ 14 ] |= ((f[ 35 - 30 ] >>  7 )&0x1) <<  6
    r[ 14 ] |= ((f[ 52 - 30 ] >>  3 )&0x1) <<  7
    r[ 15 ] |= ((f[ 38 - 30 ] >>  7 )&0x1) <<  0
    r[ 15 ] |= ((f[ 55 - 30 ] >>  3 )&0x1) <<  1
    r[ 15 ] |= ((f[ 40 - 30 ] >>  3 )&0x1) <<  2
    r[ 15 ] |= ((f[ 56 - 30 ] >>  7 )&0x1) <<  3
    r[ 15 ] |= ((f[ 41 - 30 ] >>  7 )&0x1) <<  4
    r[ 15 ] |= ((f[ 58 - 30 ] >>  3 )&0x1) <<  5
    r[ 15 ] |= ((f[ 43 - 30 ] >>  3 )&0x1) <<  6
    r[ 15 ] |= ((f[ 59 - 30 ] >>  7 )&0x1) <<  7

    return r
