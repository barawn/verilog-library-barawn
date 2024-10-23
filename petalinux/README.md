# PetaLinux patch recipes

This is a collection of recipes to patch PetaLinux
with additional functionality. Generally they're based
on 2022.1, so you may need to modify things.

I don't know if there's a way to package recipes
for tooled integration, so you'll probably need to
integrate these by hand if needed.

* partial_readback - implements Linux partial FPGA readback via horrible hacks
* jtag_console - backport of the DCC uart serialization option
* efuse_access - modify PMU firmware to enable accessing efuses via nvmem

There are more details in a README.md in each directory.

## bitbake-env

``bitbake-env`` is a bash script which gets you access to the raw
bitbake/yocto tools under PetaLinux. This is hilariously buried
in UG1144 Chapter 11 as steps 4-8, so I just collated all of them.

Put it under ``project-spec`` and source it if you need to access
the bitbake/yocto/oe stuff.