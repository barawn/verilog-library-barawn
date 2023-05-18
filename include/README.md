# Interfaces
Modern FPGAs connect submodules together using standardized interfaces, like WISHBONE,
AXI4, AXI4-Lite, and AXI4-Stream. However, actually connecting these interfaces together
in HDL can be error-prone and tedious.

Yes, VHDL and SystemVerilog both have methods of working around this – custom types,
interfaces. Both of these have strong drawbacks: neither of them can be easily connected
to existing modules and IP, for instance. This is also why many people lean on block
diagrams when they first start out with Vivado as well, but of course block diagrams
become incredibly tedious as well and have no mechanism for generated code.

For Verilog, there is another tool in the arsenal which is rarely used - the Verilog
preprocessor – which has none of these drawbacks. (VHDL is slowly gaining the use of a
preprocessor, but it is limited to conditional code at this point, which is strange
considering how boilerplate VHDL tends to be).

Interface definitions using the Verilog preprocessor have been built up for several
standard types:

* AXI4-Stream minimal (meaning tdata, tvalid, tready only)
* AXI4-Lite
* AXI4
* WISHBONE
* DRP

plus several “proprietary” interfaces used by the former Dini group firmware.

## Interface Headers

Interface definitions are in interface.vh here. To add this file to your repository, using
project_init.tcl-style buildup, do something like

```
add_include_dir [ file join verilog-library-barawn include ]
```

to your project_init.tcl script. Note that this assumes that verilog-library-barawn has been
added as a submodule to your repository in the top directory – if it is elsewhere, alter the
script accordingly (e.g. if it is in a “submodules” directory, do file join submodules
verilog-library-barawn include, etc.).

## Using Interfaces

All interfaces in interfaces.vh follow a very similar convention.
* Interfaces all have a unique prefix (or `NO_PREFIX) before their “standard signal names”
  e.g. an AXI4-Stream port interface with signals m_axis_tdata, m_axis_tready, m_axis_tvalid
  has prefix “m_axis_” 
  * These prefixes typically end in an underscore.
* Interfaces are created by a `DEFINE_xx_IF macro (where xx is a short name for the interface).
  This declares the signals (not ports) to connect modules. These macros take parameters
  describing the interface (data width, address width, etc.)
* Interfaces are connected by a `CONNECT_xx_IF( port_prefix, if_prefix) macro which connect
  an interface with prefix if_prefix to a port with prefix port_prefix. This convention makes
  the macro “look like” a standard connect (which lists port name first, then signal connecting)
* Interface port names in a module are created with a `HOST_NAMED_PORTS_IF or
  `TARGET_NAMED_PORTS_IF macro depending on if the module is the host (interface controller)
  or the target (interface responder). Host/target may also be referred to as master/slave in
  definitions.

interfaces.vh also has a concept of a vector of interfaces, which has a suffix on the final name.
For instance:

```
wire [7:0] stream_tdata[3:0];
wire stream_tvalid[3:0];
wire stream_tready[3:0];
```

would be an interface with a suffix of [3:0]. Vectored interfaces have macros ending in “V” –
so for instance the preceding example is created by

```
`DEFINE_AXI4S_MIN_IFV( stream_ , 8, [3:0] )
```

Similarly, vectored interfaces are connected using `CONNECT_xx_IFV macros:
```
`CONNECT_AXI4S_MIN_IFV( s_axis_ , stream_ , [0] ) )
```

to pick off the individual vectored interface.

Note: Using interfaces is mostly compatible with all Xilinx IP. However you should be
careful to note that they follow the same naming convention, including case. A very small
amount of Xilinx IP bizarrely uses uppercase for AXI4 signal names, for instance. In those
cases a secondary wrapper can be created which wraps the signal names back to their
lowercase versions.

## Example

A module (stream_source) provides a basic 16-bit AXI4-Stream (“stream16_”) which goes to a
resizing module (stream_resize) where it becomes a 64-bit AXI4-Stream (“stream64_”), ending
in the final module (stream_sink).

```
`DEFINE_AXI4S_MIN_IF( stream16_ , 16 );
`DEFINE_AXI4S_MIN_IF( stream64_ , 64 );

stream_source u_source( .aclk(aclk),
                        .aresetn(aresetn),
                        `CONNECT_AXI4S_MIN_IF( m_axis_ , stream16_ ));
stream_resize u_resize( .aclk(aclk),
                        .aresetn(aresetn),
                        `CONNECT_AXI4S_MIN_IF( s_axis_ , stream16_ ),
                        `CONNECT_AXI4S_MIN_IF( m_axis_ , stream64_ ));
stream_sink u_sink( .aclk(aclk),
                    .aresetn(aresetn),
                    `CONNECT_AXI4S_MIN_IF( s_axis_ , stream64_ ));
```

## Notes

interfaces.vh is both getting big and also a bit boilerplate. I might start separating
the interfaces into their own files along with a common header, and then have "interfaces.vh"
include them all.

Not sure how to cut down on the boilerplate more, we'll see.