# Partial readback in PetaLinux

Xilinx's fpga-mgr interface only allows for full image
readback, which sucks since it takes a long time for
large FPGAs. Except it inherits this problem from
the PMU fw, which inherits the problem from the
xilfpga library.

So we patch it all. I abuse "readback_type" to pass more
information:

* bit 0: if 0, readback config registers, if 1 readback FPGA data
* bits [30:1]: starting frame address
* bit 31: if 1, do a readback capture, if 0, do a readback verify

Xilinx FPGAs have 2 types of readback:
* readback verify
* readback capture

Readback verify is basically trying to confirm a bitstream load.
Therefore you __shut down__ the FPGA first (forcing everything
back to initial state), read everything out, then start the FPGA
up again.

Readback capture actually extracts the __running state__ of the
FPGA. Doing this requires a bit more hoop-jumping, but the
FPGA stays running. The tools all basically say you need to
freeze the portion of the logic you're reading out, which
usually means stopping the clock.

Note that I do not think there's actually a difference between
the two methods when it comes to block RAM, except obviously
if you do a readback verify, you're shutting down the thing.

Readback capture is one of those "black magic" things
Xilinx gives very little information about. The earliest
answer records are some of the best - there's also XAPP1230
which Xilinx blew up all of their links to, but I've got it below.
**Important Note** - XAPP1230's Table 4 **is not a command sequence**!
It's just a random list of commands that will be used! Also
the command before the Type 2 packet in Table 5 is an FDRO read,
not write.

* [Virtex Readback|https://adaptivesupport.amd.com/s/article/8181?language=en_US]
* [XAPP1230|https://download.amd.com/docnav/documents/XAPP1230.pdf]

Also, to be clear, if you're reading the Configuration Details documents
from Xilinx, they randomly screwed up what a ``NO OP`` is around the
7 series, and because they just copy-paste things, it stuck around. 
[https://adaptivesupport.amd.com/s/question/0D54U00008kQaMhSAK/type-1-noop-confusion-0x02000000-or-0x20000000?language=en_US](It's wrong),
a Type 1 ``NO OP`` is ``0x20000000``.

Details from the early article give better detail on what the limitations
are more than "stop the clock":

1. if the design uses distributed RAM or SRL16s, reading back LUTs can
    destroy the contents if they're written while reading

2. the configuration logic overrides the address lines to BRAMs 

It's uncertain how much of this applies to more recent devices.

Note that you need to know what the frame size is to
interpret the FAR offset as a byte offset. There's also
some dummy data in the beginning which you have to jump
past.

The Python directory contains a script for doing this.
