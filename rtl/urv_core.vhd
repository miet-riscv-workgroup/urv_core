--  
-- uRV - a tiny and dumb RISC-V core
-- Copyright (c) 2015 CERN
-- Author: Tomasz Włostowski <tomasz.wlostowski@cern.ch>
-- 
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 3.0 of the License, or (at your option) any later version.
-- 
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public
-- License along with this library.
--


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;
use work.genram_pkg.all;

entity urv_core is
  generic (
    g_internal_ram_size      : integer := 65536;
    g_internal_ram_init_file : string  := "";
    g_simulation             : boolean := false;
    g_address_bits           : integer := 32
    );

  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

    cpu_rst_i : in std_logic := '0';

    -- not implemented yet ;-(
    irq_i : in std_logic_vector(7 downto 0);

    dwb_o : out t_wishbone_master_out;
    dwb_i : in  t_wishbone_master_in;

    host_slave_i : in  t_wishbone_slave_in := cc_dummy_slave_in;
    host_slave_o : out t_wishbone_slave_out
    );
end urv_core;

architecture wrapper of urv_core is

  constant c_mem_address_bits : integer := f_ceil_log2(g_internal_ram_size / 4);

  component urv_cpu is
    port(
      clk_i : in std_logic;
      rst_i : in std_logic;

      irq_i : in std_logic_vector(7 downto 0);

      im_addr_o  : out std_logic_vector(31 downto 0);
      im_data_i  : in  std_logic_vector(31 downto 0);
      im_valid_i : in  std_logic;

      dm_addr_o        : out std_logic_vector(31 downto 0);
      dm_data_s_o      : out std_logic_vector(31 downto 0);
      dm_data_l_i      : in  std_logic_vector(31 downto 0);
      dm_data_select_o : out std_logic_vector(3 downto 0);
      dm_ready_i       : in  std_logic;
      dm_store_o       : out std_logic;
      dm_load_o        : out std_logic;
      dm_load_done_i   : in  std_logic;
      dm_store_done_i  : in  std_logic
      );
  end component;

  component urv_iram
    generic (
      g_size       : integer;
      g_init_file  : string;
      g_simulation : boolean
      ); 
    port (
      clk_i : in std_logic;

      ena_i  : in  std_logic;
      wea_i  : in  std_logic;
      aa_i   : in  std_logic_vector(31 downto 0);
      bwea_i : in  std_logic_vector(3 downto 0);
      da_i   : in  std_logic_vector(31 downto 0);
      qa_o   : out std_logic_vector(31 downto 0);
      enb_i  : in  std_logic;
      web_i  : in  std_logic;
      ab_i   : in  std_logic_vector(31 downto 0);
      bweb_i : in  std_logic_vector(3 downto 0);
      db_i   : in  std_logic_vector(31 downto 0);
      qb_o   : out std_logic_vector(31 downto 0)
      );
  end component;



  signal cpu_rst, cpu_rst_d : std_logic;
  signal im_addr            : std_logic_vector(31 downto 0);
  signal im_data            : std_logic_vector(31 downto 0);
  signal im_valid           : std_logic;

  signal ha_im_addr                                : std_logic_vector(g_address_bits-1 downto 0);
  signal ha_im_wdata, ha_im_rdata                  : std_logic_vector(31 downto 0);
  signal ha_im_access, ha_im_access_d, ha_im_write : std_logic;

  signal im_addr_muxed : std_logic_vector(g_address_bits-1 downto 0);

  signal dm_addr, dm_data_s, dm_data_l                            : std_logic_vector(31 downto 0);
  signal dm_data_select                                           : std_logic_vector(3 downto 0);
  signal dm_load, dm_store, dm_load_done, dm_store_done, dm_ready : std_logic;

  signal dm_cycle_in_progress, dm_is_wishbone : std_logic;

  signal dm_mem_rdata, dm_wb_rdata : std_logic_vector(31 downto 0);
  signal dm_wb_write, dm_select_wb : std_logic;
  signal dm_data_write             : std_logic;
  
begin

  cpu_rst <= (not rst_n_i) or cpu_rst_i;

  --  Host access to the CPU memory (through instruction port)
  process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0') then
        ha_im_access   <= '0';
        ha_im_access_d <= '0';
        ha_im_write    <= '0';
      else
        
        ha_im_access   <= host_slave_i.cyc and host_slave_i.stb;
        ha_im_access_d <= ha_im_access;

        ha_im_write <= host_slave_i.cyc and host_slave_i.stb and host_slave_i.we;
        ha_im_wdata <= host_slave_i.dat;
        ha_im_addr  <= host_slave_i.adr(g_address_bits-1 downto 0);

        if ha_im_access_d = '1' then
          ha_im_access     <= '0';
          ha_im_access_d   <= '0';
          host_slave_o.ack <= '1';
          host_slave_o.dat <= ha_im_rdata;
        end if;
      end if;
    end if;
  end process;

--  dm_is_wishbone <= '1' when unsigned(dm_addr(20g_address_bits-1 downto 0)) >= g_wishbone_start else '0';
  dm_is_wishbone <= dm_addr(31);

  -- Wishbone bus arbitration / internal RAM access
  process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(rst_n_i = '0') then
        dwb_o.cyc            <= '0';
        dm_cycle_in_progress <= '0';
        dm_load_done         <= '0';
        dm_store_done        <= '0';
        dm_select_wb         <= '0';
      else
        
        if(dm_cycle_in_progress = '0') then  -- access to internal memory
          if(dm_is_wishbone = '0') then
            if(dm_store = '1') then
              dm_load_done  <= '0';
              dm_store_done <= '1';
              dm_select_wb  <= '0';
            elsif (dm_load = '1') then
              dm_load_done  <= '1';
              dm_store_done <= '0';
              dm_select_wb  <= '0';
            else
              dm_store_done <= '0';
              dm_load_done  <= '0';
              dm_select_wb  <= '0';
            end if;
          else
            if(dm_load = '1' or dm_store = '1') then
              dwb_o.cyc   <= '1';
              dwb_o.stb   <= '1';
              dwb_o.we    <= dm_store;
              dm_wb_write <= dm_store;

              dwb_o.adr <= dm_addr;
              dwb_o.dat <= dm_data_s;
              dwb_o.sel <= dm_data_select;


              dm_load_done         <= '0';
              dm_store_done        <= '0';
              dm_cycle_in_progress <= '1';
            else
              dm_store_done        <= '0';
              dm_load_done         <= '0';
              dm_cycle_in_progress <= '0';
            end if;
          end if;
        else
          if(dwb_i.stall = '0') then
            dwb_o.stb <= '0';
          end if;

          if(dwb_i.ack = '1') then
            if(dm_wb_write = '0') then
              dm_wb_rdata  <= dwb_i.dat;
              dm_select_wb <= '1';
              dm_load_done <= '1';
            else
              dm_store_done <= '1';
              dm_select_wb  <= '0';
            end if;

            dm_cycle_in_progress <= '0';
            dwb_o.cyc            <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  dm_data_l     <= dm_wb_rdata when dm_select_wb = '1' else dm_mem_rdata;
  im_addr_muxed <= ha_im_addr  when ha_im_access = '1' else im_addr(g_address_bits-1 downto 0);
  dm_ready      <= '1';

  cpu_core : urv_cpu
    port map (
      clk_i            => clk_sys_i,
      rst_i            => cpu_rst,
      irq_i            => irq_i,
      im_addr_o        => im_addr,
      im_data_i        => im_data,
      im_valid_i       => im_valid,
      dm_addr_o        => dm_addr,
      dm_data_s_o      => dm_data_s,
      dm_data_l_i      => dm_data_l,
      dm_data_select_o => dm_data_select,
      dm_ready_i       => dm_ready,
      dm_store_o       => dm_store,
      dm_load_o        => dm_load,
      dm_load_done_i   => dm_load_done,
      dm_store_done_i  => dm_store_done);

  dm_data_write <= not dm_is_wishbone and dm_store;

  U_iram : urv_iram
    generic map (
      g_size       => g_internal_ram_size,
      g_init_file  => g_internal_ram_init_file,
      g_simulation => g_simulation)
    port map (
      clk_i => clk_sys_i,

      ena_i  => '1',
      wea_i  => '0',
      bwea_i => "0000",
      aa_i   => im_addr_muxed,
      da_i   => ha_im_wdata,
      qa_o   => im_data,

      enb_i  => '1',
      bweb_i => dm_data_select,
      web_i  => dm_data_write,
      ab_i   => dm_addr,
      db_i   => dm_data_s,
      qb_o   => dm_mem_rdata
      );

  process(clk_sys_i)
  begin
    if rising_edge(clk_sys_i) then
      if(cpu_rst = '1') then
        im_valid  <= '0';
        cpu_rst_d <= '1';
      else
        cpu_rst_d <= cpu_rst;
        im_valid  <= not ha_im_access and (not cpu_rst_d);
      end if;
    end if;
  end process;


  host_slave_o.stall <= '0';
  host_slave_o.err   <= '0';
  host_slave_o.rty   <= '0';

  
end wrapper;


