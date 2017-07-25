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

module urv_exceptions
  (
   input 	 clk_i,
   input 	 rst_i,

   input 	 x_stall_i,
   input 	 x_kill_i,
  
   input 	 d_is_csr_i,
   input 	 d_is_eret_i,
  
   input [2:0] 	 d_fun_i,
   input [4:0] 	 d_csr_imm_i,
   input [11:0]  d_csr_sel_i,
  
   input [7:0] exp_irq_i,
   input       exp_tick_i,
   input       exp_breakpoint_i,
   input 	     exp_unaligned_load_i,
   input 	     exp_unaligned_store_i,
   input 	     exp_invalid_insn_i,

   input [31:0]  x_csr_write_value_i,
  
   output 	 x_exception_o,
   input [31:0]  x_exception_pc_i,
   output [31:0] x_exception_pc_o,
   output [31:0] x_exception_vector_o,
  
   output [31:0] csr_mstatus_o,
   output [31:0] csr_mip_o,
   output [31:0] csr_mie_o,
   output [31:0] csr_mtvec_o,
   output [31:0] csr_mepc_o,
   output [31:0] csr_mcause_o

   );

   

   reg [31:0] 	 csr_mepc;
   reg [31:0] 	 csr_mie;
   reg [31:0]    csr_mtvec;
   reg 		 csr_ie;

   reg [4:0] 	 csr_mcause;
   
   reg 		 exception;
   reg [4:0] 	 cause;

   reg [12:0] 	 except_vec_masked;

   assign csr_mcause_o = {27'h0, csr_mcause};
   assign csr_mepc_o = csr_mepc;
   assign csr_mie_o = csr_mie;
   assign csr_mtvec_o = csr_mtvec;
   assign csr_mstatus_o[0] = csr_ie;
   assign csr_mstatus_o[31:1] = 0;
   
   reg [31:0] 	 csr_mip;

   always@*
     begin
	csr_mip <= 0;
	csr_mip[`EXCEPT_ILLEGAL_INSN] <= except_vec_masked[0];
	csr_mip[`EXCEPT_BREAKPOINT] <= except_vec_masked[1];
	csr_mip[`EXCEPT_UNALIGNED_LOAD]<= except_vec_masked[2];
	csr_mip[`EXCEPT_UNALIGNED_STORE] <= except_vec_masked[3];
	csr_mip[`EXCEPT_TIMER] <= except_vec_masked[4];
	csr_mip[`EXCEPT_IRQ_0] <= except_vec_masked[5];
  csr_mip[`EXCEPT_IRQ_1] <= except_vec_masked[6];
  csr_mip[`EXCEPT_IRQ_2] <= except_vec_masked[7];
  csr_mip[`EXCEPT_IRQ_3] <= except_vec_masked[8];
  csr_mip[`EXCEPT_IRQ_4] <= except_vec_masked[9];
  csr_mip[`EXCEPT_IRQ_5] <= except_vec_masked[10];
  csr_mip[`EXCEPT_IRQ_6] <= except_vec_masked[11];
  csr_mip[`EXCEPT_IRQ_7] <= except_vec_masked[12];
     end
   

   assign csr_mip_o = csr_mip;
   
   
   
   always@(posedge clk_i)
     if (rst_i)
       except_vec_masked <= 0;
     else begin
	if(!x_stall_i && !x_kill_i && d_is_csr_i && d_csr_sel_i == `CSR_ID_MIP) begin
	   except_vec_masked[0]  <= x_csr_write_value_i [`EXCEPT_ILLEGAL_INSN];
	   except_vec_masked[1]  <= x_csr_write_value_i [`EXCEPT_BREAKPOINT];
	   except_vec_masked[2]  <= x_csr_write_value_i [`EXCEPT_UNALIGNED_LOAD];
	   except_vec_masked[3]  <= x_csr_write_value_i [`EXCEPT_UNALIGNED_STORE];
	   except_vec_masked[4]  <= x_csr_write_value_i [`EXCEPT_TIMER];
	   except_vec_masked[5]  <= x_csr_write_value_i [`EXCEPT_IRQ_0];
     except_vec_masked[6]  <= x_csr_write_value_i [`EXCEPT_IRQ_1];
     except_vec_masked[7]  <= x_csr_write_value_i [`EXCEPT_IRQ_2];
     except_vec_masked[8]  <= x_csr_write_value_i [`EXCEPT_IRQ_3];
     except_vec_masked[9]  <= x_csr_write_value_i [`EXCEPT_IRQ_4];
     except_vec_masked[10] <= x_csr_write_value_i [`EXCEPT_IRQ_5];
     except_vec_masked[11] <= x_csr_write_value_i [`EXCEPT_IRQ_6];
     except_vec_masked[12] <= x_csr_write_value_i [`EXCEPT_IRQ_7];
	end else begin
	  if ( exp_invalid_insn_i )
	    except_vec_masked[0] <= 1'b1;

	  if ( exp_breakpoint_i )
	    except_vec_masked[1] <= 1'b1;

	  if ( exp_unaligned_load_i )
	    except_vec_masked[2] <= 1'b1;

	  if ( exp_unaligned_store_i )
	    except_vec_masked[3] <= 1'b1;

	  if ( exp_tick_i )
	    except_vec_masked[4] <= csr_mie[`EXCEPT_TIMER] & csr_ie;

	  if( exp_irq_i[0] )
	    except_vec_masked[5] <= csr_mie[`EXCEPT_IRQ_0] & csr_ie;

    if( exp_irq_i[1] )
      except_vec_masked[6] <= csr_mie[`EXCEPT_IRQ_1] & csr_ie;

    if( exp_irq_i[2] )
      except_vec_masked[7] <= csr_mie[`EXCEPT_IRQ_2] & csr_ie;

    if( exp_irq_i[3] )
      except_vec_masked[8] <= csr_mie[`EXCEPT_IRQ_3] & csr_ie;

    if( exp_irq_i[4] )
      except_vec_masked[9] <= csr_mie[`EXCEPT_IRQ_4] & csr_ie;

    if( exp_irq_i[5] )
      except_vec_masked[10] <= csr_mie[`EXCEPT_IRQ_5] & csr_ie;

    if( exp_irq_i[6] )
      except_vec_masked[11] <= csr_mie[`EXCEPT_IRQ_6] & csr_ie;

    if( exp_irq_i[7] )
      except_vec_masked[12] <= csr_mie[`EXCEPT_IRQ_7] & csr_ie;

	end // else: !if(!x_stall_i && !x_kill_i && d_is_csr_i && d_csr_sel_i == `CSR_ID_MIP)
     end // else: !if(rst_i)
   
   always@*
     exception <= |except_vec_masked | exp_invalid_insn_i;

   reg exception_pending;

   assign x_exception_vector_o = csr_mtvec;
   
   always@*
    if(exp_invalid_insn_i || except_vec_masked[0])
      cause <= `EXCEPT_ILLEGAL_INSN;
    else if (except_vec_masked[1])
      cause <= `EXCEPT_BREAKPOINT;
    else if (except_vec_masked[2])
      cause <= `EXCEPT_UNALIGNED_LOAD;
    else if (except_vec_masked[3])
      cause <= `EXCEPT_UNALIGNED_STORE;
    else if (except_vec_masked[4])
      cause <= `EXCEPT_TIMER;
    else if (except_vec_masked[5])       
      cause <= `EXCEPT_IRQ_0;
    else if (except_vec_masked[6])       
      cause <= `EXCEPT_IRQ_1;
    else if (except_vec_masked[7])       
      cause <= `EXCEPT_IRQ_2;
    else if (except_vec_masked[8])       
      cause <= `EXCEPT_IRQ_3;
    else if (except_vec_masked[9])       
      cause <= `EXCEPT_IRQ_4;
    else if (except_vec_masked[10])       
      cause <= `EXCEPT_IRQ_5;
    else if (except_vec_masked[11])       
      cause <= `EXCEPT_IRQ_6;
    else if (except_vec_masked[12])       
      cause <= `EXCEPT_IRQ_7;
   
   always@(posedge clk_i)
     if(rst_i) 
       begin
	  csr_mepc <= 0;
	  csr_mie <= 0;
    csr_mtvec <= 'h8;
	  csr_ie <= 0;
	  exception_pending <= 0;
	  
       end else if(!x_stall_i && !x_kill_i) begin
	  if ( d_is_eret_i )
	    exception_pending <= 0;

          if ( !exception_pending && exception )
	    begin
	       csr_mepc <= x_exception_pc_i;
	       csr_mcause <= cause;
	       exception_pending <= 1;
	    end 

	  if(d_is_csr_i) begin
	     case (d_csr_sel_i)
	       `CSR_ID_MSTATUS: 
		 csr_ie <= x_csr_write_value_i[0];
	       `CSR_ID_MEPC: 
		 csr_mepc <= x_csr_write_value_i;
         `CSR_ID_MTVEC: 
     csr_mtvec <= x_csr_write_value_i;
	       `CSR_ID_MIE:
		 begin
		    csr_mie[`EXCEPT_ILLEGAL_INSN] <= 1;
		    csr_mie[`EXCEPT_BREAKPOINT] <= 1;
		    csr_mie[`EXCEPT_UNALIGNED_LOAD] <= 1;
		    csr_mie[`EXCEPT_UNALIGNED_STORE] <= 1;
		    csr_mie[`EXCEPT_TIMER] <= x_csr_write_value_i [`EXCEPT_TIMER];
		    csr_mie[`EXCEPT_IRQ_0] <= x_csr_write_value_i [`EXCEPT_IRQ_0];
        csr_mie[`EXCEPT_IRQ_1] <= x_csr_write_value_i [`EXCEPT_IRQ_1];
        csr_mie[`EXCEPT_IRQ_2] <= x_csr_write_value_i [`EXCEPT_IRQ_2];
        csr_mie[`EXCEPT_IRQ_3] <= x_csr_write_value_i [`EXCEPT_IRQ_3];
        csr_mie[`EXCEPT_IRQ_4] <= x_csr_write_value_i [`EXCEPT_IRQ_4];
        csr_mie[`EXCEPT_IRQ_5] <= x_csr_write_value_i [`EXCEPT_IRQ_5];
        csr_mie[`EXCEPT_IRQ_6] <= x_csr_write_value_i [`EXCEPT_IRQ_6];
        csr_mie[`EXCEPT_IRQ_7] <= x_csr_write_value_i [`EXCEPT_IRQ_7];
		 end
	     endcase // case (d_csr_sel_i)

	  end // if (d_is_csr_i)
       end // if (!x_stall_i && !x_kill_i)
   

   assign x_exception_pc_o = csr_mepc;
   assign x_exception_o = exception & !exception_pending;
   
endmodule // urv_exceptions



