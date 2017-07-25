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

module urv_writeback
  (
   input 	     clk_i,
   input 	     rst_i,

   input 	     w_stall_i,
   output 	     w_stall_req_o,
   
   input [2:0] 	     x_fun_i,
   input 	     x_load_i,
   input 	     x_store_i,
   
   input [31:0]      x_dm_addr_i,
   input [4:0] 	     x_rd_i,
   input [31:0]      x_rd_value_i,
   input 	     x_rd_write_i,
   input 	     x_valid_i,
   

   input [31:0]      x_shifter_rd_value_i,
   input [31:0]      x_multiply_rd_value_i,
   input [1:0] 	     x_rd_source_i,

   input [31:0]      dm_data_l_i,
   input 	     dm_load_done_i,
   input 	     dm_store_done_i,
   
   output [31:0]     rf_rd_value_o,
   output [4:0]      rf_rd_o,
   output 	     rf_rd_write_o
   );

   reg [31:0] 	 load_value;

   // generate load value
   always@*
     begin
	case (x_fun_i)
	  `LDST_B:
	    case ( x_dm_addr_i [1:0] )
	      2'b00:  load_value <= {{24{dm_data_l_i[7]}}, dm_data_l_i[7:0] };
	      2'b01:  load_value <= {{24{dm_data_l_i[15]}}, dm_data_l_i[15:8] };
	      2'b10:  load_value <= {{24{dm_data_l_i[23]}}, dm_data_l_i[23:16] };
	      2'b11:  load_value <= {{24{dm_data_l_i[31]}}, dm_data_l_i[31:24] };
	      default: load_value <= 32'hx;
	    endcase // case ( x_dm_addr_i [1:0] )
	  
	  `LDST_BU:
	    case ( x_dm_addr_i [1:0] )
	      2'b00:  load_value <= {24'h0, dm_data_l_i[7:0] };
	      2'b01:  load_value <= {24'h0, dm_data_l_i[15:8] };
	      2'b10:  load_value <= {24'h0, dm_data_l_i[23:16] };
	      2'b11:  load_value <= {24'h0, dm_data_l_i[31:24] };
	      default: load_value <= 32'hx;
	    endcase // case ( x_dm_addr_i [1:0] )
	  
	  `LDST_H:
	    case ( x_dm_addr_i [1:0] )
	      2'b00, 2'b01: load_value <= {{16{dm_data_l_i[15]}}, dm_data_l_i[15:0] };
	      2'b10, 2'b11: load_value <= {{16{dm_data_l_i[31]}}, dm_data_l_i[31:16] };
	      default: load_value <= 32'hx;
	    endcase // case ( x_dm_addr_i [1:0] )

	  `LDST_HU:
	    case ( x_dm_addr_i [1:0] )
	      2'b00, 2'b01:  load_value <= {16'h0, dm_data_l_i[15:0] };
	      2'b10, 2'b11:  load_value <= {16'h0, dm_data_l_i[31:16] };
	      default: load_value <= 32'hx;
	    endcase // case ( x_dm_addr_i [1:0] )
	    
	  `LDST_L: load_value <= dm_data_l_i;

	  default: load_value <= 32'hx;
	endcase // case (d_fun_i)
     end // always@ *

   reg rf_rd_write;
   reg [31:0] rf_rd_value;
      
   always@*
     if( x_load_i )
       rf_rd_value <= load_value;
     else if ( x_rd_source_i == `RD_SOURCE_SHIFTER )
       rf_rd_value <= x_shifter_rd_value_i;
     else if ( x_rd_source_i == `RD_SOURCE_MULTIPLY )
       rf_rd_value <= x_multiply_rd_value_i;
     else
       rf_rd_value <= x_rd_value_i;

   always@*
     if (w_stall_i)
       rf_rd_write <= 0;
     else if (x_load_i && dm_load_done_i)
       rf_rd_write <= x_valid_i;
     else
       rf_rd_write <= x_rd_write_i & x_valid_i;


   assign rf_rd_write_o = rf_rd_write;
   assign rf_rd_value_o = rf_rd_value;
   assign rf_rd_o = x_rd_i;
   assign w_stall_req_o = x_valid_i && ((x_load_i && !dm_load_done_i) || (x_store_i && !dm_store_done_i));

endmodule // urv_writeback
