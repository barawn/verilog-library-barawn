`timescale 1ns / 1ps
// This module wraps the existing round-robin arbiter for WISHBONE purposes.
// In the WISHBONE case, a request (cyc) occurs until a grant is given,
// and then the grant is held until the request is released.
module wishbone_arbiter(
		rst_i,
		clk_i,
		cyc_i,
		gnt_o
    );

	parameter NUM_MASTERS = 4;
	input rst_i;
	input clk_i;
	input [NUM_MASTERS-1:0] cyc_i;
	output [NUM_MASTERS-1:0] gnt_o;

	wire [NUM_MASTERS-1:0] grants;
	wire [NUM_MASTERS-1:0] requests;
	
	reg [NUM_MASTERS-1:0] active_grant = {NUM_MASTERS{1'b0}};
	wire any_active = |(active_grant & cyc_i);

	generate
	genvar i;
		for (i=0;i<NUM_MASTERS;i=i+1) begin : ACTIVE_GRANT_LOOP
			always @(posedge clk_i) begin : ACTIVE_GRANT_LOGIC
				if (rst_i) active_grant[i] <= 0;
				else if (!cyc_i[i]) active_grant[i] <= 0;
				else if (cyc_i[i] && grants[i]) active_grant[i] <= 1;
			end
			assign requests[i] = cyc_i[i] && !any_active;
		end
	endgenerate
	
	round_robin_arbiter #(.N(NUM_MASTERS)) u_arbiter(.rst_n(!rst_i),.clk(clk_i),.req(requests),.grant(grants));
	
	assign gnt_o = (active_grant | grants);
	// clk cyc req gnt active_grant
	// 0   1   1   0   0
	// 1   1   1   1   0
	// 2   1   0   0   1           <-- active_grant holds off all new requests
	// 3   0   0   0   1           <-- active_grant gets ignored if its cyc_i goes away (but since there's a one-cycle hold on requests, this doesn't matter)
	// 4   1   1   0   0           <-- active_grant goes away when its cyc_i goes away
	
endmodule
