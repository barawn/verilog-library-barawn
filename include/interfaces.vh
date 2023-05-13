`ifndef INTERFACES_VH_
//
// This file contains macro defines for interface connections.
// We do this because it helps ensure that the interfaces are defined
// correctly for each instance each time to reduce typos.
//

// Conventions:
// `DEFINE_(name of interface)_IF( prefix , ... ) defines wires for (name of interface) with 'prefix' before it.
// `DEFINE_(name of interface)_IFV( prefix , suffix , ... ) defines wires for (name of interface) with 'prefix' before it and 'suffix' after it
// `CONNECT_(name of interface)_IF( port_prefix, if_prefix ) connects an interface with 'if_prefix' to ports with 'port_prefix'
// `CONNECT_(name of interface)_IFV( port_prefix, if_prefix, if_suffix ) connects an interface with 'if_prefix' and 'if_suffix' to ports with 'port_prefix'
// `HOST_NAMED_PORTS_(name of interface)_IF( prefix ) defines named ports for an interface with 'prefix' before them, defined as a host (initiator, master)
// `TARGET_NAMED_PORTS_(name of interface)_IF( prefix ) defines named ports for an interface with 'prefix' before them, defined as a target (slave)
//
// suffixes are only intended to be used for vector indices, that's why you can't define them for ports

// Dumb macros so that empty prefixes/suffixes don't look weird
`define NO_PREFIX
`define NO_SUFFIX

/////////////////////////////////////////////////////////
// AXI4-Stream minimal interface: TDATA/TVALID/TREADY. //
/////////////////////////////////////////////////////////

`define DEFINE_AXI4S_MIN_IFV( prefix , suffix, width )          \
    wire [ width - 1:0] prefix``tdata``suffix;                  \
    wire prefix``tvalid``suffix;                                \
    wire prefix``tready``suffix

`define DEFINE_AXI4S_MIN_IF( prefix , width )                   \
    `DEFINE_AXI4S_MIN_IFV( prefix, `NO_SUFFIX , width )

`define CONNECT_AXI4S_MIN_IFV( port_prefix , if_prefix , if_suffix )            \
    .``port_prefix``tdata ( if_prefix``tdata``if_suffix ),                      \
    .``port_prefix``tvalid ( if_prefix``tvalid``if_suffix ),                    \
    .``port_prefix``tready ( if_prefix``tready``if_suffix )                

`define CONNECT_AXI4S_MIN_IF( port_prefix , if_prefix )                         \
    `CONNECT_AXI4S_MIN_IFV( port_prefix, if_prefix, `NO_SUFFIX )

`define NAMED_PORTS_AXI4S_MIN_IF( port_prefix , width , tohost_type, fromhost_type)         \
    fromhost_type [ width - 1:0]    port_prefix``tdata,                                     \
    fromhost_type                   port_prefix``tvalid,                                    \
    tohost_type                     port_prefix``tready

`define HOST_NAMED_PORTS_AXI4S_MIN_IF( port_prefix, width )     \
    `NAMED_PORTS_AXI4S_MIN_IF( port_prefix, width, input, output )

`define TARGET_NAMED_PORTS_AXI4S_MIN_IF( port_prefix, width )     \
    `NAMED_PORTS_AXI4S_MIN_IF( port_prefix, width, output, input )

/////////////////////////////////////////////////////////////////////
// AXI4-Stream nominal interface: TDATA/TVALID/TREADY/TKEEP/TLAST. //
/////////////////////////////////////////////////////////////////////
`define DEFINE_AXI4S_IFV( prefix, suffix, width )   \
    `DEFINE_AXI4S_MIN_IFV( prefix, suffix, width ); \
    wire [ (width/8) - 1:0] prefix``tkeep``suffix;  \
    wire prefix``tlast``suffix

`define DEFINE_AXI4S_IF( prefix, width )            \
    `DEFINE_AXI4S_IFV( prefix, `NO_SUFFIX, width )

`define CONNECT_AXI4S_IFV( port_prefix, if_prefix, if_suffix )      \
    `CONNECT_AXI4S_MIN_IFV( port_prefix, if_prefix, if_suffix ),        \
    .``port_prefix``tkeep( if_prefix``tkeep``if_suffix ),               \
    .``port_prefix``tlast( if_prefix``tlast``if_suffix )            

`define CONNECT_AXI4S_IF( port_prefix, if_prefix )                  \
    `CONNECT_AXI4S_IFV( port_prefix, if_prefix, `NO_SUFFIX )
    

`define NAMED_PORTS_AXI4S_IF( port_prefix, width, tohost_type, fromhost_type )      \
    `NAMED_PORTS_AXI4S_MIN_IF( port_prefix, width, tohost_type, fromhost_type ),    \
    fromhost_type [ width/8 - 1:0]  port_prefix``tkeep,                             \
    fromhost_type                   port_prefix``tlast


`define HOST_NAMED_PORTS_AXI4S_IF( port_prefix, width )     \
    `NAMED_PORTS_AXI4S_IF( port_prefix, width, input, output )


`define TARGET_NAMED_PORTS_AXI4S_IF( port_prefix, width )   \
    `NAMED_PORTS_AXI4S_IF( port_prefix, width, output, input )

    
/////////////////////////////////////////////////////////////
// Darklite split interface.                               //
// macro for bus definition of 64/256 split interface      //
// holy crap this saves an utter boatload of typing        //
/////////////////////////////////////////////////////////////
// convenience define
`define DEFINE_SPLIT_IFV_DMA( prefix, suffix, idx )                         \
    wire [255:0]    prefix``dma``idx``_from_host_data;                      \
    wire [13:0]     prefix``dma``idx``_from_host_ctrl;                      \
    wire            prefix``dma``idx``_from_host_valid;                     \
    wire            prefix``dma``idx``_from_host_advance;                   \
    wire [255:0]    prefix``dma``idx``_to_host_data``suffix;                \
    wire [13:0]     prefix``dma``idx``_to_host_ctrl``suffix;                \
    wire            prefix``dma``idx``_to_host_valid``suffix;               \
    wire            prefix``dma``idx``_to_host_almost_full``suffix; 
    
`define DEFINE_SPLIT_IFV( prefix, suffix )                                  \
    wire [63:0]     prefix``target_address``suffix;                         \
    wire [63:0]     prefix``target_write_data``suffix;                      \
    wire [7:0]      prefix``target_write_be``suffix;                        \
    wire            prefix``target_address_valid``suffix;                   \
    wire            prefix``target_write_enable``suffix;                    \
    wire            prefix``target_write_accept``suffix;                    \
    wire            prefix``target_read_enable``suffix;                     \
    wire [3:0]      prefix``target_request_tag``suffix;                     \
    wire [63:0]     prefix``target_read_data``suffix;                       \
    wire            prefix``target_read_accept``suffix;                     \
    wire [3:0]      prefix``target_read_data_tag``suffix;                   \
    wire            prefix``target_read_data_valid``suffix;                 \
    wire [7:0]      prefix``target_read_ctrl``suffix;                       \
    wire [7:0]      prefix``target_read_data_ctrl``suffix;                  \
    `DEFINE_SPLIT_IFV_DMA( prefix , suffix, 0);                             \
    `DEFINE_SPLIT_IFV_DMA( prefix , suffix, 1);                             \
    `DEFINE_SPLIT_IFV_DMA( prefix , suffix, 2)

`define DEFINE_SPLIT_IF( prefix )                                       \
    `DEFINE_SPLIT_IFV( prefix, `NO_SUFFIX )    

// convenience function for DMA
`define CONNECT_SPLIT_IFV_DMA( port_prefix , if_prefix, if_suffix, idx )                                        \
    .``port_prefix``dma``idx``_from_host_data       ( if_prefix``dma``idx``_from_host_data``if_suffix ),        \
    .``port_prefix``dma``idx``_from_host_ctrl       ( if_prefix``dma``idx``_from_host_ctrl``if_suffix ),        \
    .``port_prefix``dma``idx``_from_host_valid      ( if_prefix``dma``idx``_from_host_valid``if_suffix ),       \
    .``port_prefix``dma``idx``_from_host_advance    ( if_prefix``dma``idx``_from_host_advance``if_suffix ),     \
    .``port_prefix``dma``idx``_to_host_data         ( if_prefix``dma``idx``_to_host_data``if_suffix ),          \
    .``port_prefix``dma``idx``_to_host_ctrl         ( if_prefix``dma``idx``_to_host_ctrl``if_suffix ),          \
    .``port_prefix``dma``idx``_to_host_valid        ( if_prefix``dma``idx``_to_host_valid``if_suffix ),         \
    .``port_prefix``dma``idx``_to_host_almost_full  ( if_prefix``dma``idx``_to_host_almost_full``if_suffix )

// macro for port connection of split interface
`define CONNECT_SPLIT_IFV( port_prefix , if_prefix, if_suffix )                                         \
    .``port_prefix``target_address                  ( if_prefix``target_address``if_suffix ),           \
    .``port_prefix``target_write_data               ( if_prefix``target_write_data``if_suffix ),        \
    .``port_prefix``target_write_be                 ( if_prefix``target_write_be``if_suffix ),          \
    .``port_prefix``target_address_valid            ( if_prefix``target_address_valid``if_suffix ),     \
    .``port_prefix``target_write_enable             ( if_prefix``target_write_enable``if_suffix ),      \
    .``port_prefix``target_write_accept             ( if_prefix``target_write_accept``if_suffix ),      \
    .``port_prefix``target_read_enable              ( if_prefix``target_read_enable``if_suffix ),       \
    .``port_prefix``target_request_tag              ( if_prefix``target_request_tag``if_suffix ),       \
    .``port_prefix``target_read_data                ( if_prefix``target_read_data``if_suffix ),         \
    .``port_prefix``target_read_accept              ( if_prefix``target_read_accept``if_suffix ),       \
    .``port_prefix``target_read_data_tag            ( if_prefix``target_read_data_tag``if_suffix ),     \
    .``port_prefix``target_read_data_valid          ( if_prefix``target_read_data_valid``if_suffix ),   \
    .``port_prefix``target_read_ctrl                ( if_prefix``target_read_ctrl``if_suffix ),         \
    .``port_prefix``target_read_data_ctrl           ( if_prefix``target_read_data_ctrl``if_suffix ),    \
    `CONNECT_SPLIT_IFV_DMA( port_prefix, if_prefix, if_suffix, 0 ),                                     \
    `CONNECT_SPLIT_IFV_DMA( port_prefix, if_prefix, if_suffix, 1 ),                                     \
    `CONNECT_SPLIT_IFV_DMA( port_prefix, if_prefix, if_suffix, 2 )

`define CONNECT_SPLIT_IF( port_prefix, if_prefix )  \
    `CONNECT_SPLIT_IFV( port_prefix, if_prefix, `NO_SUFFIX )

`define NAMED_PORTS_SPLIT_IF_DMA( port_prefix , fromhost_type, tohost_type, idx)        \
    fromhost_type   [255:0] ``port_prefix``dma``idx``_from_host_data,                   \
    fromhost_type   [13:0]  ``port_prefix``dma``idx``_from_host_ctrl,                   \
    fromhost_type           ``port_prefix``dma``idx``_from_host_valid,                  \
    tohost_type             ``port_prefix``dma``idx``_from_host_advance,                \
    tohost_type     [255:0] ``port_prefix``dma``idx``_to_host_data,                     \
    tohost_type     [13:0]  ``port_prefix``dma``idx``_to_host_ctrl,                     \
    tohost_type             ``port_prefix``dma``idx``_to_host_valid,                    \
    fromhost_type           ``port_prefix``dma``idx``_to_host_almost_full

`define NAMED_PORTS_SPLIT_IF( port_prefix, fromhost_type, tohost_type )                 \
    fromhost_type [63:0]    ``port_prefix``target_address,                              \
    fromhost_type [63:0]    ``port_prefix``target_write_data,                           \
    fromhost_type [7:0]     ``port_prefix``target_write_be,                             \
    fromhost_type           ``port_prefix``target_address_valid,                        \
    fromhost_type           ``port_prefix``target_write_enable,                         \
    tohost_type             ``port_prefix``target_write_accept,                         \
    fromhost_type           ``port_prefix``target_read_enable,                          \
    fromhost_type [3:0]     ``port_prefix``target_request_tag,                          \
    tohost_type [63:0]      ``port_prefix``target_read_data,                            \
    tohost_type             ``port_prefix``target_read_accept,                          \
    tohost_type [3:0]       ``port_prefix``target_read_data_tag,                        \
    tohost_type             ``port_prefix``target_read_data_valid,                      \
    fromhost_type [7:0]     ``port_prefix``target_read_ctrl,                            \
    tohost_type [7:0]       ``port_prefix``target_read_data_ctrl,                       \
    `NAMED_PORTS_SPLIT_IF_DMA( port_prefix, fromhost_type, tohost_type, 0),             \
    `NAMED_PORTS_SPLIT_IF_DMA( port_prefix, fromhost_type, tohost_type, 1),             \
    `NAMED_PORTS_SPLIT_IF_DMA( port_prefix, fromhost_type, tohost_type, 2)
 
`define HOST_NAMED_PORTS_SPLIT_IF( port_prefix )    \
    `NAMED_PORTS_SPLIT_IF( port_prefix, output , input )

`define TARGET_NAMED_PORTS_SPLIT_IF( port_prefix )  \
    `NAMED_PORTS_SPLIT_IF( port_prefix, input , output )      
    
/////////////////////////////////////////////////////////////
// Darklite 64-bit combined interface.                     //
// macro for bus definition of 64-bit combined interface   //
/////////////////////////////////////////////////////////////
`define DEFINE_COMBINED_IFV( prefix , suffix )                          \
    wire         prefix``interface_ready``suffix;                       \
    wire [63:0]  prefix``register_write_address``suffix;                \
    wire [63:0]  prefix``register_write_data``suffix;                   \
    wire [7:0]   prefix``register_write_be``suffix;                     \
    wire         prefix``register_write_enable``suffix;                 \
    wire [63:0]  prefix``register_read_address``suffix;                 \
    wire [7:0]   prefix``register_request_tag``suffix;                  \
    wire         prefix``register_read_enable``suffix;                  \
    wire [63:0]  prefix``register_read_data``suffix;                    \
    wire [7:0]   prefix``register_read_data_tag``suffix;                \
    wire         prefix``register_read_data_valid``suffix

`define DEFINE_COMBINED_IF( prefix )                                    \
    `DEFINE_COMBINED_IFV( prefix, `NO_SUFFIX )

// macro for port connection of 64-bit combined interface
`define CONNECT_COMBINED_IFV( port_prefix , if_prefix , if_suffix )                             \
    .``port_prefix``interface_ready          ( if_prefix``interface_ready``if_suffix),          \
    .``port_prefix``register_write_address   ( if_prefix``register_write_address``if_suffix),   \
    .``port_prefix``register_write_data      ( if_prefix``register_write_data``if_suffix),      \
    .``port_prefix``register_write_be        ( if_prefix``register_write_be``if_suffix),        \
    .``port_prefix``register_write_enable    ( if_prefix``register_write_enable``if_suffix),    \
    .``port_prefix``register_read_address    ( if_prefix``register_read_address``if_suffix),    \
    .``port_prefix``register_request_tag     ( if_prefix``register_request_tag``if_suffix),     \
    .``port_prefix``register_read_enable     ( if_prefix``register_read_enable``if_suffix),     \
    .``port_prefix``register_read_data       ( if_prefix``register_read_data``if_suffix),       \
    .``port_prefix``register_read_data_tag   ( if_prefix``register_read_data_tag``if_suffix),   \
    .``port_prefix``register_read_data_valid ( if_prefix``register_read_data_valid``if_suffix)

`define CONNECT_COMBINED_IF( port_prefix , if_prefix )          \
    `CONNECT_COMBINED_IFV(port_prefix, if_prefix, `NO_SUFFIX )

// macro for named port definition of 64-bit combined interface. see below for simpler macros for host/target
`define NAMED_PORTS_COMBINED_IF( port_prefix , fromhost_type, tohost_type)          \
    tohost_type                 port_prefix``interface_ready,                       \
    fromhost_type       [63:0]  port_prefix``register_write_address,                \
    fromhost_type       [63:0]  port_prefix``register_write_data,                   \
    fromhost_type       [7:0]   port_prefix``register_write_be,                     \
    fromhost_type               port_prefix``register_write_enable,                 \
    fromhost_type       [63:0]  port_prefix``register_read_address,                 \
    fromhost_type       [7:0]   port_prefix``register_request_tag,                  \
    fromhost_type               port_prefix``register_read_enable,                  \
    tohost_type         [63:0]  port_prefix``register_read_data,                    \
    tohost_type         [7:0]   port_prefix``register_read_data_tag,                \
    tohost_type                 port_prefix``register_read_data_valid
// convenience macro for defining a port at the host (master) side
`define HOST_NAMED_PORTS_COMBINED_IF( port_prefix )                                 \
    `NAMED_PORTS_COMBINED_IF( port_prefix , output, input)
`define TARGET_NAMED_PORTS_COMBINED_IF( port_prefix )                               \
    `NAMED_PORTS_COMBINED_IF( port_prefix , input, output)
    
// AXI4-Lite interface macros.
//
// The "CONNECT" macros also exist for individual channels
// for connecting half-connected channels like exist in some Xilinx
// modules. We don't do this for the define or port definition
// macros because unused ports can just be ignored.
//
`define DEFINE_AXI4L_IFV( prefix , suffix , address_width, data_width )             \
    wire    [ address_width -1:0]       prefix``awaddr``suffix;                     \
    wire                                prefix``awvalid``suffix;                    \
    wire                                prefix``awready``suffix;                    \
    wire    [ data_width -1:0]          prefix``wdata``suffix;                      \
    wire                                prefix``wvalid``suffix;                     \
    wire                                prefix``wready``suffix;                     \
    wire    [ ( data_width /8 ) -1:0]   prefix``wstrb``suffix;                      \
    wire    [1:0]                       prefix``bresp``suffix;                      \
    wire                                prefix``bvalid``suffix;                     \
    wire                                prefix``bready``suffix;                     \
    wire    [ address_width -1:0]       prefix``araddr``suffix;                     \
    wire                                prefix``arvalid``suffix;                    \
    wire                                prefix``arready``suffix;                    \
    wire    [ data_width -1:0]          prefix``rdata``suffix;                      \
    wire    [1:0]                       prefix``rresp``suffix;                      \
    wire                                prefix``rvalid``suffix;                     \
    wire                                prefix``rready``suffix

`define DEFINE_AXI4L_IF( prefix , address_width, data_width )                       \
    `DEFINE_AXI4L_IFV( prefix , `NO_SUFFIX , address_width, data_width )

`define CONNECT_AXI4L_IFV( port_prefix, if_prefix , if_suffix )             \
    `CONNECT_AXI4L_AW_IFV( port_prefix, if_prefix , if_suffix ),            \
    `CONNECT_AXI4L_W_IFV( port_prefix, if_prefix, if_suffix ),              \
    `CONNECT_AXI4L_B_IFV( port_prefix, if_prefix, if_suffix ),              \
    `CONNECT_AXI4L_AR_IFV( port_prefix, if_prefix, if_suffix ),             \
    `CONNECT_AXI4L_R_IFV( port_prefix, if_prefix, if_suffix )

`define CONNECT_AXI4L_IF( port_prefix, if_prefix )                          \
    `CONNECT_AXI4L_IFV( port_prefix , if_prefix , `NO_SUFFIX )

// Auxiliary AXI4-Lite connect macros, for the modules that don't have all
// channels.

`define CONNECT_AXI4L_AW_IFV( port_prefix, if_prefix , if_suffix )          \
    .``port_prefix``awaddr          ( if_prefix``awaddr``if_suffix ),       \
    .``port_prefix``awvalid         ( if_prefix``awvalid``if_suffix ),      \
    .``port_prefix``awready         ( if_prefix``awready``if_suffix )

`define CONNECT_AXI4L_AW_IF( port_prefix , if_prefix )              \
    `CONNECT_AXI4L_AW_IFV( port_prefix, if_prefix, `NO_SUFFIX )

`define CONNECT_AXI4L_W_IFV( port_prefix, if_prefix , if_suffix )                       \
    .``port_prefix``wdata           ( if_prefix``wdata``if_suffix  ),                   \
    .``port_prefix``wvalid          ( if_prefix``wvalid``if_suffix  ),                  \
    .``port_prefix``wready          ( if_prefix``wready``if_suffix  ),                  \
    .``port_prefix``wstrb           ( if_prefix``wstrb``if_suffix  )

`define CONNECT_AXI4L_W_IF( port_prefix , if_prefix )               \
    `CONNECT_AXI4L_W_IFV( port_prefix, if_prefix, `NO_SUFFIX )

`define CONNECT_AXI4L_B_IFV( port_prefix, if_prefix , if_suffix)                        \
    .``port_prefix``bresp           ( if_prefix``bresp``if_suffix  ),                   \
    .``port_prefix``bvalid          ( if_prefix``bvalid``if_suffix  ),                  \
    .``port_prefix``bready          ( if_prefix``bready``if_suffix  )

`define CONNECT_AXI4L_B_IF( port_prefix, if_prefix )                            \
    `CONNECT_AXI4L_B_IFV( port_prefix, if_prefix, `NO_SUFFIX )
    
`define CONNECT_AXI4L_AR_IFV( port_prefix, if_prefix , if_suffix)                       \
    .``port_prefix``araddr          ( if_prefix``araddr``if_suffix  ),                  \
    .``port_prefix``arvalid         ( if_prefix``arvalid``if_suffix  ),                 \
    .``port_prefix``arready         ( if_prefix``arready``if_suffix  )

`define CONNECT_AXI4L_AR_IF( port_prefix, if_prefix )                           \
    `CONNECT_AXI4L_AR_IFV( port_prefix , if_prefix , `NO_SUFFIX )
    
`define CONNECT_AXI4L_R_IFV( port_prefix, if_prefix , if_suffix)                        \
    .``port_prefix``rdata           ( if_prefix``rdata``if_suffix  ),                   \
    .``port_prefix``rresp           ( if_prefix``rresp``if_suffix  ),                   \
    .``port_prefix``rvalid          ( if_prefix``rvalid``if_suffix  ),                  \
    .``port_prefix``rready          ( if_prefix``rready``if_suffix  )

`define CONNECT_AXI4L_R_IF( port_prefix , if_prefix )                           \
    `CONNECT_AXI4L_R_IFV( port_prefix , if_prefix, `NO_SUFFIX )

`define NAMED_PORTS_AXI4L_IF( port_prefix , address_width, data_width, fromhost_type , tohost_type )    \
    fromhost_type   [ address_width -1:0]   port_prefix``awaddr,                                        \
    fromhost_type                           port_prefix``awvalid,                                       \
    tohost_type                             port_prefix``awready,                                       \
    fromhost_type   [ data_width -1:0]      port_prefix``wdata,                                         \
    fromhost_type                           port_prefix``wvalid,                                        \
    tohost_type                             port_prefix``wready,                                        \
    fromhost_type   [( data_width /8)-1:0]  port_prefix``wstrb,                                         \
    tohost_type     [1:0]                   port_prefix``bresp,                                         \
    tohost_type                             port_prefix``bvalid,                                        \
    fromhost_type                           port_prefix``bready,                                        \
    fromhost_type   [ address_width -1:0]   port_prefix``araddr,                                        \
    fromhost_type                           port_prefix``arvalid,                                       \
    tohost_type                             port_prefix``arready,                                       \
    tohost_type     [ data_width -1:0]      port_prefix``rdata,                                         \
    tohost_type     [1:0]                   port_prefix``rresp,                                         \
    tohost_type                             port_prefix``rvalid,                                        \
    fromhost_type                           port_prefix``rready
 
 `define HOST_NAMED_PORTS_AXI4L_IF( port_prefix, address_width, data_width )    \
    `NAMED_PORTS_AXI4L_IF( port_prefix , address_width, data_width, output , input )
 `define TARGET_NAMED_PORTS_AXI4L_IF( port_prefix, address_width, data_width )    \
       `NAMED_PORTS_AXI4L_IF( port_prefix , address_width, data_width, input , output )

// Full AXI interface.
// A full AXI interface still totally contains an AXI-Lite interface, but it adds:
// 2-bit A[R/W]burst
// 4-bit A[R/W]cache
// x-bit A[R/W]id + [R/B]id
// 8-bit A[R/W]len
// 1-bit A[R/W]lock
// 3-bit A[R/W]prot
// 4-bit A[R/W]qos
// 3-bit A[R/W]size
// N-bit A[R/W]user
// 1-bit [R/W]last
`define DEFINE_AXI4_IFV( prefix , suffix , address_width, data_width , id_width, user_width )   \
    `DEFINE_AXI4L_IFV( prefix, suffix, address_width, data_width );                             \
    wire [1:0] prefix``awburst``suffix;                                                         \
    wire [3:0] prefix``awcache``suffix;                                                         \
    wire [7:0] prefix``awlen``suffix;                                                           \
    wire prefix``awlock``suffix;                                                                \
    wire [2:0] prefix``awprot``suffix;                                                          \
    wire [3:0] prefix``awqos``suffix;                                                           \
    wire [2:0] prefix``awsize``suffix;                                                          \
    wire [ id_width -1:0] prefix``awid``suffix;                                                 \
    wire [ user_width -1:0] prefix``awuser``suffix;                                             \
    wire [1:0] prefix``arburst``suffix;                                                         \
    wire [3:0] prefix``arcache``suffix;                                                         \
    wire [7:0] prefix``arlen``suffix;                                                           \
    wire prefix``arlock``suffix;                                                                \
    wire [2:0] prefix``arprot``suffix;                                                          \
    wire [3:0] prefix``arqos``suffix;                                                           \
    wire [2:0] prefix``arsize``suffix;                                                          \
    wire [ id_width -1:0] prefix``arid``suffix;                                                 \
    wire [ user_width -1:0] prefix``aruser``suffix;                                             \
    wire [ id_width -1:0] prefix``rid``suffix;                                                  \
    wire prefix``rlast``suffix;                                                                 \
    wire [ id_width -1:0] prefix``bid``suffix;                                                  \
    wire prefix``wlast``suffix
    
`define DEFINE_AXI4_IF( prefix , address_width, data_width, id_width, user_width )              \
    `DEFINE_AXI4_IFV( prefix , `NO_SUFFIX , address_width, data_width , id_width, user_width )

`define CONNECT_AXI4_IFV( port_prefix, if_prefix , if_suffix )             \
    `CONNECT_AXI4_AW_IFV( port_prefix, if_prefix , if_suffix ),            \
    `CONNECT_AXI4_W_IFV( port_prefix, if_prefix, if_suffix ),              \
    `CONNECT_AXI4_B_IFV( port_prefix, if_prefix, if_suffix ),              \
    `CONNECT_AXI4_AR_IFV( port_prefix, if_prefix, if_suffix ),             \
    `CONNECT_AXI4_R_IFV( port_prefix, if_prefix, if_suffix )
    
`define CONNECT_AXI4_IF( port_prefix, if_prefix )                          \
    `CONNECT_AXI4_IFV( port_prefix , if_prefix , `NO_SUFFIX )

// add burst, cache, len, lock, prot, qos, size, id, user    
`define CONNECT_AXI4_AW_IFV( port_prefix, if_prefix , if_suffix )          \
    `CONNECT_AXI4L_AW_IFV( port_prefix, if_prefix, if_suffix ),             \
    .``port_prefix``awburst ( if_prefix``awburst``if_suffix ),              \
    .``port_prefix``awcache ( if_prefix``awcache``if_suffix ),              \
    .``port_prefix``awlen   ( if_prefix``awlen``if_suffix ),                \
    .``port_prefix``awlock  ( if_prefix``awlock``if_suffix ),               \
    .``port_prefix``awprot  ( if_prefix``awprot``if_suffix ),               \
    .``port_prefix``awqos   ( if_prefix``awqos``if_suffix ),                \
    .``port_prefix``awsize  ( if_prefix``awsize``if_suffix ),               \
    .``port_prefix``awid    ( if_prefix``awid``if_suffix ),                 \
    .``port_prefix``awuser  ( if_prefix``awuser``if_suffix )

`define CONNECT_AXI4_AW_IF( port_prefix, if_prefix )    \
    `CONNECT_AXI4_AW_IFV( port_prefix, if_prefix, `NO_SUFFIX )

// add burst, cache, len, lock, prot, qos, size, id, user        
`define CONNECT_AXI4_AR_IFV( port_prefix, if_prefix , if_suffix )          \
    `CONNECT_AXI4L_AR_IFV( port_prefix, if_prefix, if_suffix ),             \
    .``port_prefix``arburst ( if_prefix``arburst``if_suffix ),              \
    .``port_prefix``arcache ( if_prefix``arcache``if_suffix ),              \
    .``port_prefix``arlen   ( if_prefix``arlen``if_suffix ),                \
    .``port_prefix``arlock  ( if_prefix``arlock``if_suffix ),               \
    .``port_prefix``arprot  ( if_prefix``arprot``if_suffix ),               \
    .``port_prefix``arqos   ( if_prefix``arqos``if_suffix ),                \
    .``port_prefix``arsize  ( if_prefix``arsize``if_suffix ),               \
    .``port_prefix``arid    ( if_prefix``arid``if_suffix ),                 \
    .``port_prefix``aruser  ( if_prefix``aruser``if_suffix )

`define CONNECT_AXI4_AR_IF( port_prefix, if_prefix )    \
    `CONNECT_AXI4_AR_IFV( port_prefix, if_prefix, `NO_SUFFIX )

// R just adds RID and RLAST
`define CONNECT_AXI4_R_IFV( port_prefix, if_prefix, if_suffix )         \
    `CONNECT_AXI4L_R_IFV( port_prefix, if_prefix, if_suffix ),          \
    .``port_prefix``rid ( if_prefix``rid``if_suffix ),                  \
    .``port_prefix``rlast ( if_prefix``rlast``if_suffix )
    
`define CONNECT_AXI4_R_IF( port_prefix, if_prefix )     \
    `CONNECT_AXI4_R_IFV( port_prefix, if_prefix, `NO_SUFFIX )
    
// W adds only WLAST   
`define CONNECT_AXI4_W_IFV( port_prefix, if_prefix, if_suffix )         \
    `CONNECT_AXI4L_W_IFV( port_prefix, if_prefix, if_suffix ),          \
    .``port_prefix``wlast ( if_prefix``wlast``if_suffix )

`define CONNECT_AXI4_W_IF( port_prefix, if_prefix )     \
    `CONNECT_AXI4_W_IFV( port_prefix, if_prefix, `NO_SUFFIX )
    
// B adds BID only
`define CONNECT_AXI4_B_IFV( port_prefix, if_prefix, if_suffix )         \
    `CONNECT_AXI4L_B_IFV( port_prefix, if_prefix, if_suffix ),          \
    .``port_prefix``bid( if_prefix``bid``if_suffix )
    
`define CONNECT_AXI4_B_IF( port_prefix, if_prefix )     \
    `CONNECT_AXI4_B_IFV( port_prefix, if_prefix, `NO_SUFFIX )
    
`define NAMED_PORTS_AXI4_IF( port_prefix , address_width, data_width, id_width, user_width, fromhost_type , tohost_type )    \
    `NAMED_PORTS_AXI4L_IF( port_prefix, address_width, data_width, fromhost_type, tohost_type );    \
    fromhost_type [1:0] port_prefix``awburst;                                                       \
    fromhost_type [3:0] port_prefix``awcache;                                                       \
    fromhost_type [7:0] port_prefix``awlen;                                                         \
    fromhost_type port_prefix``awlock;                                                              \
    fromhost_type [2:0] port_prefix``awprot;                                                        \
    fromhost_type [3:0] port_prefix``awqos;                                                         \
    fromhost_type [2:0] port_prefix``awsize;                                                        \
    fromhost_type [ id_width -1:0] port_prefix``awid;                                               \
    fromhost_type [ user_width -1:0] port_prefix``awuser;                                           \
    fromhost_type [1:0] port_prefix``arburst;                                                       \
    fromhost_type [3:0] port_prefix``arcache;                                                       \
    fromhost_type [7:0] port_prefix``arlen;                                                         \
    fromhost_type port_prefix``arlock;                                                              \
    fromhost_type [2:0] port_prefix``arprot;                                                        \
    fromhost_type [3:0] port_prefix``arqos;                                                         \
    fromhost_type [2:0] port_prefix``arsize;                                                        \
    fromhost_type [ id_width -1:0] port_prefix``arid;                                               \
    fromhost_type [ user_width -1:0] port_prefix``aruser;                                           \
    tohost_type [ id_width -1:0] port_prefix``rid;                                                  \
    tohost_type port_prefix``rlast;                                                                 \
    tohost_type [ id_width -1:0] port_prefix``bid;                                                  \
    fromhost_type port_prefix``wlast
         
 `define HOST_NAMED_PORTS_AXI4_IF( port_prefix, address_width, data_width, id_width, user_width )    \
    `NAMED_PORTS_AXI4_IF( port_prefix , address_width, data_width, id_width, user_width, output , input )
 `define TARGET_NAMED_PORTS_AXI4_IF( port_prefix, address_width, data_width, id_width, user_width )    \
    `NAMED_PORTS_AXI4_IF( port_prefix , address_width, data_width, id_width, user_width, input , output )
        
/////////////////////////////////////////////////////////
// WISHBONE (very basic for now!)
/////////////////////////////////////////////////////////
//
// READ THIS:
//   WISHBONE defines work the same (or suffixed version with V if you want a vector):
//     `DEFINE_WB_IF( prefix , address_width, data_width );
//   As do host/port named ports:
//     `HOST_NAMED_PORTS_WB_IF( port_prefix , address_width, data_width ),
//   But there are now 3 connect macros you might use. The 2 most common are (again, add V for suffixed version):
//     `CONNECT_WBM_IFM( port_prefix, if_prefix ),
//     `CONNECT_WBS_IFM( port_prefix, if_prefix),
//   Note the IFM!! These connect an interface to a master (host) module and slave (target) module, respectively.
//   These work either if you are connecting a `DEFINEd interface to a slave/master module OR if you are connecting
//   a master module's port interface to a submodule.
//
//   There is ALSO a new connect:
//     `CONNECT_WBS_IFS( port_prefix, if_prefix ),
//   THIS works if you are connecting a slave module's interface to a submodule! i.e. if your hierarchy looks like:
//
//   top
//    |-- wb_master
//      |-- wb_master_implementation
//    |-- wb_slave_top
//      |-- wb_slave_registers
//
//   you would use `DEFINE_WB_IF in "top" (creates the interface), use `CONNECT_WBM_IFM to connect it to
//   wb_master AND ALSO to connect it to wb_master_implementation (and any modules below that).
//
//   You would use `CONNECT_WBS_IFM to connnect the interface to wb_slave_top.
//   You would use `CONNECT_WBS_IFS to connect wb_slave_top's port to wb_slave_registers (and any other modules below that).
//
// NOTE: wb_dat_i means it has a prefix of "wb_"!
//
//
// Details:
//
// WISHBONE is a little annoying because the names of the signals swap around. This means we effectively have
// two naming conventions: a host-named convention (M) and a target-named convention (S).
//
// We therefore have to define how the signals are named and how the ports are named. This means we end up with
// 4 (!) connect macros: connect target-named port to host named interface, connect host-named port to target named
// interface , connect host-named port to host named interface, connect target-named port to target-named interface.
//
// One of these (connect host-named port to target-named interface) is basically unused because we define our interface named
// as if it's a host. We include it for completeness.
//
// The others are used:
// host-named port to host-named interface: connect bus to host module OR
//                                          pass interface to sub-module inside host
// target-named port to host-named interface: connect bus to target module
// target-named port to target-named interface: pass interface to sub-module
//                                              inside target
//
// By convention we define how the port signals are named in the first part after CONNECT (e.g. CONNECT_WBS means ports
// are named as a target) and how the interface signals by the second part (CONNECT_WBS_IFS means connect ports named
// as target to interface named as target).

// By convention, we define a SRC signal as one that comes from the HOST
//                we define a SNK signal as one that comes from the TARGET

// Bit of trickery.
`define WB_HOST 1
`undef WB_TARGET

`define BUILD_WB_SRC_NAME( prefix, name, thistype , suffix ) \
  `ifdef thistype                                            \
    prefix``name``_o``suffix                                 \
  `else                                                      \
    prefix``name``_i``suffix                                 \
  `endif

`define BUILD_WB_SNK_NAME( prefix, name, thistype , suffix ) \
  `ifdef thistype                                            \
    prefix``name``_i``suffix                                 \
  `else                                                      \
    prefix``name``_o``suffix                                 \
  `endif

`define BUILD_WB_SRC_PORT( prefix, name, thistype , suffix ) \
  `ifdef thistype                                            \
    .``prefix``name``_o``suffix                                 \
  `else                                                      \
    .``prefix``name``_i``suffix                                 \
  `endif

`define BUILD_WB_SNK_PORT( prefix, name, thistype , suffix ) \
  `ifdef thistype                                            \
    .``prefix``name``_i``suffix                                 \
  `else                                                      \
    .``prefix``name``_o``suffix                                 \
  `endif

// Now we can do
// `BUILD_WB_SRC_PORT( pprefix , adr , WB_HOST , `NO_SUFFIX) ( `BUILD_WB_SRC_NAME( iprefix , adr, WB_HOST , `NO_SUFFIX ) ),
// and this will autogenerate the directions for a host port to host named connection.

// Macro for the above. ptype is the port type, ctype is the connection type.
`define WB_SRC_CONNECTV( pfx , ipfx, nm, ptype , ctype , sfx )        \
  `BUILD_WB_SRC_PORT( pfx , nm , ptype , sfx ) ( `BUILD_WB_SRC_NAME( ipfx , nm , ctype , sfx ) )

`define WB_SRC_CONNECT( pfx , ipfx, nm, ptype, ctype ) \
  `WB_SRC_CONNECTV( pfx , ipfx, nm, ptype, ctype, `NO_SUFFIX )

`define WB_SNK_CONNECTV( pfx , ipfx, nm, ptype , ctype , sfx )        \
  `BUILD_WB_SNK_PORT( pfx , nm , ptype , sfx ) ( `BUILD_WB_SNK_NAME( ipfx , nm , ctype , sfx ) )

`define WB_SNK_CONNECT( pfx , ipfx, nm, ptype, ctype ) \
  `WB_SRC_CONNECTV( pfx , ipfx, nm, ptype, ctype, `NO_SUFFIX )

// Macros for named port definitions
`define WB_SRC_NAMED_PORT( pfx , wpfx, nm, ptype ) \
  `ifdef ptype                               \
     output wpfx `BUILD_WB_SRC_NAME( pfx , nm, ptype, `NO_SUFFIX )     \
  `else                                                           \
     input wpfx `BUILD_WB_SRC_NAME( pfx , nm, ptype, `NO_SUFFIX )      \
  `endif

// Macros for named port definitions
`define WB_SNK_NAMED_PORT( pfx , wpfx, nm, ptype ) \
  `ifdef ptype                               \
     input wpfx `BUILD_WB_SNK_NAME( pfx , nm, ptype, `NO_SUFFIX )     \
  `else                                                           \
     output wpfx `BUILD_WB_SNK_NAME( pfx , nm, ptype, `NO_SUFFIX )      \
  `endif



///// Actual WISHBONE definitions. These are the dumb WISHBONE
///// connections for now, I'll probably add a WBB3 or WBB4 or
///// whatever interface which tacks on the additional signals.
`define DEFINE_WB_IFV( prefix , address_width, data_width, suffix ) \
  wire [ data_width - 1:0] prefix``dat_i``suffix;                   \
  wire [ data_width - 1:0] prefix``dat_o``suffix;                   \
  wire [ address_width - 1:0] prefix``adr_o``suffix;                \
  wire [ (data_width/8)-1:0] prefix``sel_o``suffix;                 \ 
  wire prefix``cyc_o``suffix;                                       \
  wire prefix``stb_o``suffix;                                       \
  wire prefix``we_o``suffix;                                        \
  wire prefix``ack_i``suffix;                                       \
  wire prefix``rty_i``suffix;                                       \
  wire prefix``err_i``suffix

`define DEFINE_WB_IF(prefix, address_width, data_width) \
    `DEFINE_WB_IFV( prefix, address_width, data_width, `NO_SUFFIX )

// generic connect macro, where you specify the types
`define CONNECT_WB_IFV( port_prefix , if_prefix, port_type, if_type, suffix) \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, dat, port_type, if_type, suffix), \
    `WB_SNK_CONNECTV( port_prefix, if_prefix, dat, port_type, if_type, suffix), \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, adr, port_type, if_type, suffix), \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, sel, port_type, if_type, suffix), \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, cyc, port_type, if_type, suffix), \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, stb, port_type, if_type, suffix), \
    `WB_SRC_CONNECTV( port_prefix, if_prefix, we, port_type, if_type, suffix),  \
    `WB_SNK_CONNECTV( port_prefix, if_prefix, ack, port_type, if_type, suffix), \
    `WB_SNK_CONNECTV( port_prefix, if_prefix, rty, port_type, if_type, suffix), \
    `WB_SNK_CONNECTV( port_prefix, if_prefix, err, port_type, if_type, suffix)

// non-vectored version
`define CONNECT_WB_IF( port_prefix, if_prefix, port_type, if_type ) \
    `CONNECT_WB_IFV( port_prefix, if_prefix, port_type, if_type, `NO_SUFFIX )
    
// Connect host-named interface to host-named port
`define CONNECT_WBM_IFMV( port_prefix, if_prefix, suffix ) \
  `CONNECT_WB_IFV( port_prefix, if_prefix, WB_HOST, WB_HOST, suffix)

`define CONNECT_WBM_IFM( port_prefix, if_prefix ) \
  `CONNECT_WB_IFV( port_prefix, if_prefix, WB_HOST, WB_HOST, `NO_SUFFIX)
    
// Connect host-named interface to target-named port
`define CONNECT_WBS_IFMV( port_prefix, if_prefix, suffix ) \
  `CONNECT_WB_IF( port_prefix, if_prefix, WB_TARGET, WB_HOST, suffix)

`define CONNECT_WBS_IFM( port_prefix, if_prefix ) \
  `CONNECT_WB_IFV( port_prefix, if_prefix, WB_TARGET, WB_HOST, `NO_SUFFIX)

// Connect target-named interface to target-named port
`define CONNECT_WBS_IFSV( port_prefix, if_prefix, suffix ) \
  `CONNECT_WB_IFV( port_prefix, if_prefix, WB_TARGET, WB_TARGET, suffix)

`define CONNECT_WBS_IFS( port_prefix, if_prefix ) \
  `CONNECT_WB_IFV( port_prefix, if_prefix, WB_TARGET, WB_TARGET, `NO_SUFFIX)

// Connect target-named interface to host-named port (you shouldn't need this!)
//`define CONNECT_WBM_IFS( port_prefix, if_prefix ) \
//  `CONNECT_WB_IF( port_prefix, if_prefix, WB_HOST, WB_TARGET)

// Create named ports in a module based on type
`define NAMED_PORTS_WB_IF( port_prefix , address_width, data_width , port_type ) \
    `WB_SRC_NAMED_PORT( port_prefix , [data_width-1:0], dat, port_type ),  \
    `WB_SNK_NAMED_PORT( port_prefix , [data_width-1:0], dat, port_type ),  \
    `WB_SRC_NAMED_PORT( port_prefix , [address_width-1:0], adr, port_type ), \
    `WB_SRC_NAMED_PORT( port_prefix , [(data_width/8)-1:0], sel, port_type ), \
    `WB_SRC_NAMED_PORT( port_prefix , `NO_PREFIX, cyc, port_type ), \
    `WB_SRC_NAMED_PORT( port_prefix , `NO_PREFIX, sel, port_type ), \
    `WB_SRC_NAMED_PORT( port_prefix , `NO_PREFIX, we, port_type ), \
    `WB_SNK_NAMED_PORT( port_prefix , `NO_PREFIX, ack, port_type ), \
    `WB_SNK_NAMED_PORT( port_prefix , `NO_PREFIX, rty, port_type ), \
    `WB_SNK_NAMED_PORT( port_prefix , `NO_PREFIX, err, port_type )
    
// Create host ports in a module
`define HOST_NAMED_PORTS_WB_IF( port_prefix, address_width, data_width ) \
    `NAMED_PORTS_WB_IF( port_prefix, address_width, data_width, WB_HOST )
    
// Create target ports in a module
`define TARGET_NAMED_PORTS_WB_IF( port_prefix, address_width, data_width ) \
    `NAMED_PORTS_WB_IF( port_prefix, address_width, data_width, WB_HOST )
    

`endif // INTERFACES_VH_
