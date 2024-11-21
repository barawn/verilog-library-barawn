# Force word (32-bit) alignment when bitstream loading

Bitstreams need to be 32-bit aligned when loaded via PM API,
otherwise the PMU needs to copy it and it is sloooow.

This patch is a backport of

https://github.com/Xilinx/linux-xlnx/commit/a0bf4b4e7ec838da5986d33ba75e047347be1017

to PetaLinux 2022.1. Since some of the other APIs/function calls
changed as well that commit won't apply cleanly because there's too
much context in the patch and the committer changed a few other things
pointlessly so even a fuzzy patch won't work straight out.