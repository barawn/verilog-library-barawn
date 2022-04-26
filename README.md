# Verilog library of modules

"hdl" contains synthesizable modules, "sim" contains behavioral modules.

There is also a Vivado_init.tcl in the top directory which can be
placed in the appropriate directory as found at

https://support.xilinx.com/s/article/53090?language=en_US

(or added to additional entries)

This contains a replacement for open_project which looks for a
project_init.tcl script in either the project directory
or, if the project directory ends in "vivado_project"
(a Git managed repository) the directory above.

(It also ups the number of threads to 16)

I highly recommend adding this.