// Dummy WISHBONE slave module.
// Used to easily terminate unused busses so that
// interconnects can be planned with expansion easily.
`include "interfaces.vh"
// Needs to be parameterized obviously.
// Doesn't need a clock since it just combinatorially
// acks.
//
// Ports are named with wb prefix (wb_cyc_i, etc.)
module wbs_dummy #( parameter ADDRESS_WIDTH = 16,
		    parameter DATA_WIDTH = 32 )
   ( 
     // Handy thing about the interface defines is that parameters
     // are fine since they just get text-substituted.
     `TARGET_NAMED_PORTS_WB_IF( wb, ADDRESS_WIDTH, DATA_WIDTH )
     );

   assign wb_ack_o = wb_cyc_i && wb_stb_i;
   assign wb_err_o = 1'b0;
   assign wb_rty_o = 1'b0;

   assign wb_dat_o = {DATA_WIDTH{1'b0}};   
   
endmodule // wbs_dummy

   
						
		   
