// Dummy WISHBONE master module.
// Used to easily terminate unused busses so that
// interconnects can be planned with expansion easily.
`include "interfaces.vh"
// Needs to be parameterized obviously.
//
// Ports are named with wb prefix (wb_cyc_i, etc.)
module wbm_dummy #( parameter ADDRESS_WIDTH = 16,
		    parameter DATA_WIDTH = 32 )
   ( 
     // Handy thing about the interface defines is that parameters
     // are fine since they just get text-substituted.
     `HOST_NAMED_PORTS_WB_IF( wb, ADDRESS_WIDTH, DATA_WIDTH )
     );

   assign wb_cyc_o = 1'b0;
   assign wb_stb_o = 1'b0;
   assign wb_we_o = 1'b0;
   assign wb_adr_o = {ADDRESS_WIDTH{1'b0}};
   assign wb_dat_o = {DATA_WIDTH{1'b0}};   
   assign wb_sel_o = {(DATA_WIDTH/8){1'b0}};
   
endmodule // wbs_dummy

   
						
		   
