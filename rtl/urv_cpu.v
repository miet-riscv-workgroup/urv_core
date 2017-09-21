/*
 
 uRV - a tiny and dumb RISC-V core
 Copyright (c) 2015 CERN
 Author: Tomasz Włostowski <tomasz.wlostowski@cern.ch>

 This library is free software; you can redistribute it and/or
 modify it under the terms of the GNU Lesser General Public
 License as published by the Free Software Foundation; either
 version 3.0 of the License, or (at your option) any later version.

 This library is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public
 License along with this library.
 
*/

`include "urv_defs.v"

`timescale 1ns/1ps

module urv_cpu
  #(
    parameter g_timer_frequency = 1000000,
    parameter g_clock_frequency = 100000000,
    parameter g_with_hw_divide = 0,
    parameter g_with_hw_debug = 0,
    parameter g_debug_breakpoints = 6
   ) 
   (
   input 	 clk_i,
   input 	 rst_i,

   input [7:0]	 irq_i,
   
   // instruction mem I/F
   output [31:0] im_addr_o,
   input [31:0]  im_data_i,
   input 	 im_valid_i,

   // data mem I/F
   output [31:0] dm_addr_o,
   output [31:0] dm_data_s_o,
   input [31:0]  dm_data_l_i,
   output [3:0]  dm_data_select_o,
   input 	 dm_ready_i,

   output 	 dm_store_o,
   output 	 dm_load_o,
   input 	 dm_load_done_i,
   input 	 dm_store_done_i 
   );


   // pipeline control
   wire 	 f_stall;
   wire 	 w_stall;
   wire 	 x_stall;
   wire 	 x_kill;
   wire 	 f_kill;
   wire 	 d_stall;
   wire 	 d_kill;
   wire 	 d_stall_req;
   wire 	 w_stall_req;
   wire 	 x_stall_req;

   // X1->F stage interface
   wire [31:0] 	 x2f_pc_bra;
   wire 	 x2f_bra;
   
   // F->D stage interface
   wire [31:0] 	 f2d_pc, f2d_ir;
   wire 	 f2d_ir_valid;
   wire 	 f2d_valid;

   // D->RF interface
   wire [4:0] 	 rf_rs1, rf_rs2;

   // X2/W->RF interface
   wire [4:0] 	 rf_rd;
   wire [31:0] 	 rf_rd_value;
   wire 	 rf_rd_write;
   
   // D->X1 stage interface
   wire 	 d2x_valid;
   wire [31:0] 	 d2x_pc;
   wire [4:0] 	 d2x_rs1;
   wire [4:0] 	 d2x_rs2;
   wire [4:0] 	 d2x_rd;
   wire [4:0] 	 d2x_shamt;
   wire [2:0] 	 d2x_fun;
   wire [4:0] 	 d2x_opcode;
   wire 	 d2x_shifter_sign;
   wire 	 d2x_is_load, d2x_is_store, d2x_is_undef;
   wire [31:0] 	 d2x_imm;
   wire 	 d2x_is_signed_compare;
   wire 	 d2x_is_signed_alu_op;
   wire 	 d2x_is_add_o;
   wire 	 d2x_is_shift_o;
   wire [2:0] 	 d2x_rd_source;
   wire 	 d2x_rd_write;
   wire [11:0] 	 d2x_csr_sel;
   wire [4:0] 	 d2x_csr_imm;
   wire 	 d2x_is_csr, d2x_is_eret, d2x_csr_load_en;
   wire [31:0] 	 d2x_alu_op1, d2x_alu_op2;
   wire  	 d2x_use_op1, d2x_use_op2;

   // X1/M->X2/W interface
   wire [4:0] 	 x2w_rd;
   wire [31:0] 	 x2w_rd_value;
   wire [31:0] 	 x2w_rd_shifter;
   wire [31:0] 	 x2w_rd_multiply;
   wire [31:0] 	 x2w_dm_addr;
   wire 	 x2w_rd_write;
   wire [2:0] 	 x2w_fun;
   wire 	 x2w_store;
   wire 	 x2w_load;
   wire [1:0] 	 x2w_rd_source;
   wire 	 x2w_valid;

   // Register file signals
   wire [31:0] 	 x_rs2_value, x_rs1_value;
   wire [31:0] 	 rf_bypass_rd_value = x2w_rd_value;
   wire  	 rf_bypass_rd_write = rf_rd_write && !x2w_load; // multiply/shift too?
   
   // misc stuff
   wire [63:0] 	 csr_time, csr_cycles;
   
   urv_fetch fetch
     (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .im_addr_o(im_addr_o),
      .im_data_i(im_data_i),
      .im_valid_i(im_valid_i),

      // pipe control
      .f_stall_i(f_stall),
      .f_kill_i(f_kill),

      // to D stage
      .f_valid_o(f2d_valid),
      .f_ir_o(f2d_ir),
      .f_pc_o(f2d_pc),

      // from X1 stage (jumps)
      .x_pc_bra_i(x2f_pc_bra),
      .x_bra_i(x2f_bra)
      );


   urv_decode decode
     (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // pipe control
      .d_stall_i(d_stall),
      .d_kill_i(d_kill),
      .d_stall_req_o(d_stall_req),

      // from F stage
      .f_ir_i(f2d_ir),
      .f_pc_i(f2d_pc),
      .f_valid_i(f2d_valid),

      // to RF (regfile)
      .rf_rs1_o(rf_rs1),
      .rf_rs2_o(rf_rs2),

      // to X1 stage
      .x_valid_o(d2x_valid),
      .x_pc_o(d2x_pc),
      .x_rs1_o(d2x_rs1),
      .x_rs2_o(d2x_rs2),
      .x_imm_o(d2x_imm),
      .x_rd_o(d2x_rd),
      .x_shamt_o(d2x_shamt),
      .x_fun_o(d2x_fun),
      .x_opcode_o(d2x_opcode),
      .x_shifter_sign_o(d2x_shifter_sign),
      .x_is_signed_compare_o(d2x_is_signed_compare),
      .x_is_signed_alu_op_o(d2x_is_signed_alu_op),
      .x_is_add_o(d2x_is_add),
      .x_is_shift_o(d2x_is_shift),
      .x_is_load_o(d2x_is_load),
      .x_is_store_o(d2x_is_store),
      .x_is_undef_o(d2x_is_undef),
      .x_rd_source_o(d2x_rd_source),
      .x_rd_write_o(d2x_rd_write),
      .x_csr_sel_o (d2x_csr_sel),
      .x_csr_imm_o (d2x_csr_imm),
      .x_is_csr_o (d2x_is_csr),
      .x_is_eret_o (d2x_is_eret),
      .x_alu_op1_o(d2x_alu_op1),
      .x_alu_op2_o(d2x_alu_op2),
      .x_use_op1_o(d2x_use_op1),
      .x_use_op2_o(d2x_use_op2)
      );

   // Register File (RF)
   urv_regfile regfile
     (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .d_stall_i(d_stall),

      .rf_rs1_i(rf_rs1),
      .rf_rs2_i(rf_rs2),

      .d_rs1_i(d2x_rs1),
      .d_rs2_i(d2x_rs2),

      .x_rs1_value_o(x_rs1_value),
      .x_rs2_value_o(x_rs2_value),
      
      .w_rd_i(rf_rd),
      .w_rd_value_i(rf_rd_value),
      .w_rd_store_i(rf_rd_write),

      .w_bypass_rd_write_i(rf_bypass_rd_write),
      .w_bypass_rd_value_i(rf_bypass_rd_value)
      );
 
   // Execute 1/Memory stage (X1/M)
   urv_exec execute
     (
      .clk_i(clk_i),
      .rst_i(rst_i),
      
      .irq_i ( irq_i ),

      // pipe control
      .x_stall_i(x_stall),
      .x_kill_i(x_kill),
      .x_stall_req_o(x_stall_req),

      // from register file
      .rf_rs1_value_i(x_rs1_value),
      .rf_rs2_value_i(x_rs2_value),

      // from D stage
      .d_valid_i(d2x_valid),
      .d_is_csr_i ( d2x_is_csr ),
      .d_is_eret_i ( d2x_is_eret ),
      .d_csr_imm_i ( d2x_csr_imm ),
      .d_csr_sel_i (d2x_csr_sel),
      .d_pc_i(d2x_pc),
      .d_rd_i(d2x_rd),
      .d_fun_i(d2x_fun),
      .d_imm_i(d2x_imm),
      .d_is_signed_compare_i(d2x_is_signed_compare),
      .d_is_signed_alu_op_i(d2x_is_signed_alu_op),
      .d_is_add_i(d2x_is_add),
      .d_is_shift_i(d2x_is_shift),
      .d_is_load_i(d2x_is_load),
      .d_is_store_i(d2x_is_store),
      .d_is_undef_i(d2x_is_undef),
      .d_alu_op1_i(d2x_alu_op1),
      .d_alu_op2_i(d2x_alu_op2),
      .d_use_op1_i(d2x_use_op1),
      .d_use_op2_i(d2x_use_op2),
      .d_rd_source_i(d2x_rd_source),
      .d_rd_write_i(d2x_rd_write), 
      .d_opcode_i(d2x_opcode),
      .d_shifter_sign_i(d2x_shifter_sign),
  
      // to F stage (branches)
      .f_branch_target_o (x2f_pc_bra), // fixme: consistent naming
      .f_branch_take_o (x2f_bra),

      // to X2/W stage
      .w_fun_o(x2w_fun),
      .w_load_o(x2w_load),
      .w_store_o(x2w_store),
      .w_valid_o(x2w_valid),
      .w_dm_addr_o(x2w_dm_addr),
      .w_rd_o(x2w_rd),
      .w_rd_value_o(x2w_rd_value),
      .w_rd_write_o(x2w_rd_write),
      .w_rd_source_o ( x2w_rd_source),
      .w_rd_shifter_o ( x2w_rd_shifter),
      .w_rd_multiply_o ( x2w_rd_multiply),

      // Data memory I/F
      .dm_addr_o(dm_addr_o),
      .dm_data_s_o(dm_data_s_o),
      .dm_data_select_o(dm_data_select_o),
      .dm_store_o(dm_store_o),
      .dm_load_o(dm_load_o),
      .dm_ready_i(dm_ready_i),

      // CSR registers/timer stuff
      .csr_time_i (csr_time),
      .csr_cycles_i (csr_cycles),
      .timer_tick_i (sys_tick)
   );

   // Execute 2/Writeback stage
   urv_writeback writeback
     (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // pipe control
      .w_stall_i(w_stall),
      .w_stall_req_o(w_stall_req),

      // from X1 stage
      .x_fun_i(x2w_fun),
      .x_load_i(x2w_load),
      .x_store_i(x2w_store),
      .x_valid_i(x2w_valid),
      .x_rd_i(x2w_rd),
      .x_rd_source_i(x2w_rd_source),
      .x_rd_value_i(x2w_rd_value),
      .x_rd_write_i(x2w_rd_write),
      .x_shifter_rd_value_i ( x2w_rd_shifter),
      .x_multiply_rd_value_i ( x2w_rd_multiply),
      .x_dm_addr_i(x2w_dm_addr),

      // Data memory I/F
      .dm_data_l_i(dm_data_l_i),
      .dm_load_done_i(dm_load_done_i),
      .dm_store_done_i(dm_store_done_i),
      
      // to register file
      .rf_rd_value_o(rf_rd_value),
      .rf_rd_o(rf_rd),
      .rf_rd_write_o(rf_rd_write)
   );

   // Built-in timer
   urv_timer 
     #(
       .g_timer_frequency(g_timer_frequency),
       .g_clock_frequency(g_clock_frequency)
       ) 
   ctimer 
     (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .csr_time_o(csr_time),
      .csr_cycles_o(csr_cycles),
      
      .sys_tick_o(sys_tick)
      );

   // pipeline invalidation logic after a branch
   reg 		 x2f_bra_d0, x2f_bra_d1;

   always@(posedge clk_i)
     if(rst_i) begin
	x2f_bra_d0 <= 0;
	x2f_bra_d1 <= 0;
     end else if (!x_stall) begin
	x2f_bra_d0 <= x2f_bra;
	x2f_bra_d1 <= x2f_bra_d0;
     end
   
   // pipeline control
   assign f_stall = x_stall_req || w_stall_req || d_stall_req;
   assign x_stall = x_stall_req || w_stall_req;
   assign d_stall = x_stall_req || w_stall_req;
   assign w_stall = 0;

   assign x_kill = x2f_bra || x2f_bra_d0 || x2f_bra_d1;
   assign d_kill = x2f_bra || x2f_bra_d0;
   assign f_kill = x2f_bra;
   
endmodule // urv_cpu

   

   
