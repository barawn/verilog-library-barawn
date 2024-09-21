# Partial readback in PetaLinux

Xilinx's fpga-mgr interface only allows for full image
readback, which sucks since it takes a long time for
large FPGAs. Except it inherits this problem from
the PMU fw, which inherits the problem from the
xilfpga library.

So we patch it all. I abuse "readback_type" to allow the
upper 31 bits to be the starting FAR, and then add
"readback_len" to specify the number of bytes.

Note that you need to know what the frame size is to
interpret the FAR offset as a byte offset. There's also
some dummy data in the beginning which you have to jump
past.

The Python directory contains a script for doing this.
