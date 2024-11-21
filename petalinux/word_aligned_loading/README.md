# Force word (32-bit) alignment when bitstream loading

Bitstreams need to be 32-bit aligned when loaded via PM API,
otherwise the PMU needs to copy it and it is sloooow.

So if you run across situations like [this](https://adaptivesupport.amd.com/s/question/0D52E00006iHjKOSA0/zynq-mpsoc-fpgautil-download-speed?language=en_US)
or [this](https://adaptivesupport.amd.com/s/question/0D52E00006hpYlHSAU/partial-configuration-time-is-too-long-more-than-3-seconds?language=en_US), you
probably tried to load an unaligned file. This happens if you load
the ``.bit`` file instead of the ``.bin`` file, but if you want to
keep the ``.bit`` file, use this.

This patch is a backport of

https://github.com/Xilinx/linux-xlnx/commit/a0bf4b4e7ec838da5986d33ba75e047347be1017

to PetaLinux 2022.1. Since some of the other APIs/function calls
changed as well that commit won't apply cleanly because there's too
much context in the patch and the committer changed a few other things
pointlessly so even a fuzzy patch won't work straight out.