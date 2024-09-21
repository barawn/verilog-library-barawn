# PetaLinux patch recipes

This is a collection of recipes to patch PetaLinux
with additional functionality. Generally they're based
on 2022.1, so you may need to modify things.

I don't know if there's a way to package recipes
for tooled integration, so you'll probably need to
integrate these by hand if needed.

* partial_readback - implements Linux partial FPGA readback via horrible hacks
* jtag_console - backport of the DCC uart serialization option

There are more details in a README.md in each directory.