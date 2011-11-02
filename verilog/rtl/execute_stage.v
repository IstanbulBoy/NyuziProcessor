`include "timescale.v"

//
// - Performs arithmetic operations
// - Detects conditional branches and resolves them
// - Issues address to data cache for tag check
// - Handles bypassing of register results that have not been committed
//     to register file.
//

module execute_stage(
	input					clk,
	input [31:0]			instruction_i,
	output reg[31:0]		instruction_o,
	input [31:0]			pc_i,
	output reg[31:0]		pc_o,
	input [31:0] 			scalar_value1_i,
	input [4:0]				scalar_sel1_i,
	input [31:0] 			scalar_value2_i,
	input [4:0]				scalar_sel2_i,
	input [511:0] 			vector_value1_i,
	input [4:0]				vector_sel1_i,
	input [511:0] 			vector_value2_i,
	input [4:0]				vector_sel2_i,
	input [31:0] 			immediate_i,
	input [2:0] 			mask_src_i,
	input 					op1_is_vector_i,
	input [1:0] 			op2_src_i,
	input					store_value_is_vector_i,
	output reg[31:0]		store_value_o,
	input	 				has_writeback_i,
	input [4:0]				writeback_reg_i,
	input					writeback_is_vector_i,	
	output reg 				has_writeback_o,
	output reg[4:0]			writeback_reg_o,
	output reg				writeback_is_vector_o,
	output reg[15:0]		mask_o,
	output reg[511:0]		result_o,
	input [5:0]				alu_op_i,
	output reg[31:0]		daddress_o,
	output 					daccess_o,
	output [3:0]			lane_select_i,
	output reg[3:0]			lane_select_o,
	input [4:0]				bypass1_register,		// mem access stage
	input					bypass1_has_writeback,
	input					bypass1_is_vector,
	input [511:0]			bypass1_value,
	input [15:0]			bypass1_mask,
	input [4:0]				bypass2_register,		// writeback stage
	input					bypass2_has_writeback,
	input					bypass2_is_vector,
	input [511:0]			bypass2_value,
	input [15:0]			bypass2_mask,
	input [4:0]				bypass3_register,		// post writeback
	input					bypass3_has_writeback,
	input					bypass3_is_vector,
	input [511:0]			bypass3_value,
	input [15:0]			bypass3_mask,
	output reg				rollback_request_o,
	output reg[31:0]		rollback_address_o,
	input					flush_i);
	
	reg[511:0]				op1;
	reg[511:0] 				op2;
	wire[511:0] 			alu_result;
	reg[31:0]				store_value_nxt;
	reg[15:0]				mask_nxt;
	wire[511:0]				vector_value1_bypassed;
	wire[511:0] 			vector_value2_bypassed;
	reg[31:0] 				scalar_value1_bypassed;
	reg[31:0] 				scalar_value2_bypassed;
	wire[3:0]				c_op_type;
	
	initial
	begin
		instruction_o = 0;
		store_value_o = 0;
		has_writeback_o = 0;
		writeback_reg_o = 0;
		writeback_is_vector_o = 0;
		mask_o = 0;
		result_o = 0;
		op1 = 0;
		op2 = 0;
		store_value_nxt = 0;
		mask_nxt = 0;
		scalar_value1_bypassed = 0;
		scalar_value2_bypassed = 0;
		daddress_o = 0;
		rollback_request_o = 0;
		rollback_address_o = 0;
	end

	// scalar_value1_bypassed
	always @*
	begin
		if (scalar_sel1_i == 31)
			scalar_value1_bypassed = pc_i;
		else if (scalar_sel1_i == writeback_reg_o && has_writeback_o
			&& !writeback_is_vector_o)
			scalar_value1_bypassed = result_o;
		else if (scalar_sel1_i == bypass1_register && bypass1_has_writeback
			&& !bypass1_is_vector)
			scalar_value1_bypassed = bypass1_value[31:0];
		else if (scalar_sel1_i == bypass2_register && bypass2_has_writeback
			&& !bypass2_is_vector)
			scalar_value1_bypassed = bypass2_value[31:0];
		else if (scalar_sel1_i == bypass3_register && bypass3_has_writeback
			&& !bypass3_is_vector)
			scalar_value1_bypassed = bypass3_value[31:0];
		else 
			scalar_value1_bypassed = scalar_value1_i;	
	end

	always @*
	begin
		if (scalar_sel2_i == 31)
			scalar_value2_bypassed = pc_i;
		else if (scalar_sel2_i == writeback_reg_o && has_writeback_o
			&& !writeback_is_vector_o)
			scalar_value2_bypassed = result_o[31:0];
		else if (scalar_sel2_i == bypass1_register && bypass1_has_writeback
			&& !bypass1_is_vector)
			scalar_value2_bypassed = bypass1_value[31:0];
		else if (scalar_sel2_i == bypass2_register && bypass2_has_writeback
			&& !bypass2_is_vector)
			scalar_value2_bypassed = bypass2_value[31:0];
		else if (scalar_sel2_i == bypass3_register && bypass3_has_writeback
			&& !bypass3_is_vector)
			scalar_value2_bypassed = bypass3_value[31:0];
		else 
			scalar_value2_bypassed = scalar_value2_i;	
	end

	// vector_value1_bypassed
	vector_bypass_unit vbu1(
		.register_sel_i(vector_sel1_i), 
		.data_i(vector_value1_i),	
		.value_o(vector_value1_bypassed),
		.bypass1_register_i(writeback_reg_o),	
		.bypass1_write_i(has_writeback_o && writeback_is_vector_o),
		.bypass1_value_i(result_o),
		.bypass1_mask_i(mask_o),
		.bypass2_register_i(bypass1_register),	
		.bypass2_write_i(bypass1_has_writeback && bypass1_is_vector),
		.bypass2_value_i(bypass1_value),
		.bypass2_mask_i(bypass1_mask),
		.bypass3_register_i(bypass2_register),	
		.bypass3_write_i(bypass2_has_writeback && bypass2_is_vector),
		.bypass3_value_i(bypass2_value),
		.bypass3_mask_i(bypass2_mask),
		.bypass4_register_i(bypass3_register),	
		.bypass4_write_i(bypass3_has_writeback && bypass3_is_vector),
		.bypass4_value_i(bypass3_value),
		.bypass4_mask_i(bypass3_mask));

	// vector_value2_bypassed
	vector_bypass_unit vbu2(
		.register_sel_i(vector_sel2_i), 
		.data_i(vector_value2_i),	
		.value_o(vector_value2_bypassed),
		.bypass1_register_i(writeback_reg_o),	
		.bypass1_write_i(has_writeback_o && writeback_is_vector_o),
		.bypass1_value_i(result_o),
		.bypass1_mask_i(mask_o),
		.bypass2_register_i(bypass1_register),	
		.bypass2_write_i(bypass1_has_writeback && bypass1_is_vector),
		.bypass2_value_i(bypass1_value),
		.bypass2_mask_i(bypass1_mask),
		.bypass3_register_i(bypass2_register),	
		.bypass3_write_i(bypass2_has_writeback && bypass2_is_vector),
		.bypass3_value_i(bypass2_value),
		.bypass3_mask_i(bypass2_mask),
		.bypass4_register_i(bypass3_register),	
		.bypass4_write_i(bypass3_has_writeback && bypass3_is_vector),
		.bypass4_value_i(bypass3_value),
		.bypass4_mask_i(bypass3_mask));

	// op1
	always @*
	begin
		if (op1_is_vector_i)
			op1 = vector_value1_bypassed;
		else
			op1 = {16{scalar_value1_bypassed}};
	end

	// op2
	always @*
	begin
		case (op2_src_i)
			2'b00: op2 = {16{scalar_value2_bypassed}};
			2'b01: op2 = vector_value2_bypassed;
			2'b10: op2 = {16{immediate_i}};
		endcase
	end
	
	// mask
	always @*
	begin
		case (mask_src_i)
			3'b000:	mask_nxt = scalar_value1_bypassed[15:0];
			3'b001:	mask_nxt = ~scalar_value1_bypassed[15:0];
			3'b010:	mask_nxt = scalar_value2_bypassed[15:0];
			3'b011:	mask_nxt = ~scalar_value2_bypassed[15:0];
			3'b100:	mask_nxt = 16'hffff;
		endcase
	end
	
	// store_value_nxt
	always @*
	begin
		if (store_value_is_vector_i)
			store_value_nxt = vector_value2_bypassed >> ((15 - lane_select_i) * 32);
		else
			store_value_nxt = scalar_value2_bypassed;
	end	

	single_cycle_alu alu(
		.operation_i(alu_op_i),
		.operand1_i(op1),
		.operand2_i(op2),
		.result_o(alu_result));

	assign c_op_type = instruction_i[28:25];
	
	// We issue the tag request in parallel with the execute stage, so these
	// are not registered.
	always @*
	begin
		case (c_op_type)
			4'b0110, 4'b0111, 4'b1000:	// Block vector access
				daddress_o = alu_result[31:0] + lane_select_i * 4;
			
			4'b1001, 4'b1010, 4'b1011:	// Strided vector access 
				// XXX should not instantiate a multiplier here.  We can probably
				// use a adder further up the pipeline and push the offset here.
				// Also, note that we use op1 as the base instead of alu_result,
				// since the immediate value is not applied to the base pointer.
				daddress_o = op1[31:0] + lane_select_i * immediate_i;

			4'b1100, 4'b1101, 4'b1110:	// Scatter/Gather access
				daddress_o = alu_result >> ((15 - lane_select_i) * 32);
		
			default: // Scalar load
				daddress_o = alu_result[31:0];
		endcase
	end

	// Note that we check the mask bit for this lane.
	assign daccess_o = instruction_i[31:30] == 2'b10
		&& (mask_nxt & (16'h8000 >> lane_select_i)) != 0;

	// Branch control
	always @*
	begin
		if (instruction_i[31:28] == 4'b1111)
		begin
			case (instruction_i[27:26])
				2'b00: rollback_request_o = op1[15:0] == 16'hffff;	// ball
				2'b01: rollback_request_o = op1 == 16'd0; // bzero
				2'b10: rollback_request_o = op1 != 16'd0; // bnzero
				2'b11: rollback_request_o = 1; // goto
			endcase
			
			rollback_address_o = pc_i + { {11{instruction_i[25]}}, instruction_i[25:5] };
		end
		else
		begin
			rollback_request_o = 0;
			rollback_address_o = 0;
		end
	end

	always @(posedge clk)
	begin
		if (flush_i)
		begin
			instruction_o 				<= #1 0;
			writeback_reg_o 			<= #1 0;
			writeback_is_vector_o 		<= #1 0;
			has_writeback_o 			<= #1 0;
			result_o 					<= #1 0;
			store_value_o				<= #1 0;
			mask_o						<= #1 0;
			lane_select_o				<= #1 0;
			pc_o						<= #1 0;
		end
		else
		begin
			instruction_o 				<= #1 instruction_i;
			writeback_reg_o 			<= #1 writeback_reg_i;
			writeback_is_vector_o 		<= #1 writeback_is_vector_i;
			has_writeback_o 			<= #1 has_writeback_i;
			result_o 					<= #1 alu_result;
			store_value_o				<= #1 store_value_nxt;
			mask_o						<= #1 mask_nxt;
			lane_select_o				<= #1 lane_select_i;
			pc_o						<= #1 pc_i;
		end
	end
endmodule
