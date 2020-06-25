-- This file is copyright by Grant Searle 2014
-- Grant Searle's web site http://searle.hostei.com/grant/    
-- Grant Searle's "multicomp" page at http://searle.hostei.com/grant/Multicomp/index.html
--
-- Changes to this code by Doug Gilliland 2019
--	48K (external) RAM version
--
-- Jumper the FPGA selects the VDU/Serial port
-- Install to make serial port default
-- Remove jumper to make the VDU default
--
-- 115,200 baud serial port
-- Hardware handshake RTS/CTS
--
-- djrm conversion to sdram begin, june23 2020
-- pll and sdram fsm copied from Sytse van Slooten's pdp2011 DE0
-- this version has sdram component

library ieee;
use ieee.std_logic_1164.all;
use  IEEE.STD_LOGIC_ARITH.all;
use  IEEE.STD_LOGIC_UNSIGNED.all;

entity Microcomputer is
	port(
		n_reset		: in std_logic;
		i_CLOCK_50	: in std_logic;

      dram_addr 	: out std_logic_vector(11 downto 0);
      dram_dq 		: inout std_logic_vector(15 downto 0);
      dram_cas_n 	: out std_logic;
      dram_ras_n 	: out std_logic;
      dram_we_n 	: out std_logic;
      dram_cs_n 	: out std_logic;
      dram_clk 	: out std_logic;
      dram_cke 	: out std_logic;
      dram_ba_1 	: out std_logic;
      dram_ba_0 	: out std_logic;
      dram_udqm 	: out std_logic;
      dram_ldqm 	: out std_logic;
 		
		rxd1			: in std_logic;
		txd1			: out std_logic;
		cts1			: in std_logic;
		rts1			: out std_logic;
		
		videoR0		: out std_logic;
		videoG0		: out std_logic;
		videoB0		: out std_logic;
		videoR1		: out std_logic;
		videoG1		: out std_logic;
		videoB1		: out std_logic;
		hSync			: out std_logic;
		vSync			: out std_logic;

		ps2Clk		: inout std_logic;
		ps2Data		: inout std_logic;

		i_pbutton   : in std_logic_vector(1 downto 0);
		o_BUZZER    : out std_logic;
		serSelect	: in std_logic := '1'
	);
end Microcomputer;

architecture struct of Microcomputer is

	signal n_WR							: std_logic;
	signal n_RD							: std_logic;
	signal cpuAddress					: std_logic_vector(15 downto 0);
	signal cpuDataOut					: std_logic_vector(7 downto 0);
	signal cpuDataIn					: std_logic_vector(7 downto 0);

	signal basRomData					: std_logic_vector(7 downto 0);
	signal interface1DataOut		: std_logic_vector(7 downto 0);
	signal internalRam1DataOut		: std_logic_vector(7 downto 0);
	signal interface2DataOut		: std_logic_vector(7 downto 0);
	
	signal w_displayed_number		: std_logic_vector(31 downto 0);

--	signal n_memWR						: std_logic :='1';
--	signal n_memRD 					: std_logic :='1';

	signal dram_match 				: std_logic;
	signal sdramDataOut 				: std_logic_vector(7 downto 0);

	signal n_int1						: std_logic :='1';	
	signal n_int2						: std_logic :='1';	
	
	signal n_internalRamCS			: std_logic :='1';
	signal n_externalRamCS			: std_logic :='1';
	signal n_basRomCS					: std_logic :='1';
	signal n_interface1CS			: std_logic :='1';
	signal n_interface2CS			: std_logic :='1';
	
	signal cpuClock					: std_logic;
	signal resetLow					: std_logic := '1';

   signal serialCount         	: std_logic_vector(15 downto 0) := x"0000";
   signal serialCount_d       	: std_logic_vector(15 downto 0);
   signal serialEn            	: std_logic;

	 
begin
	
   o_BUZZER <= '1'; -- sound off
		
	-- ____________________________________________________________________________________
	-- 6809 CPU
	-- works with Version 1.26
	-- Does not work with Version 1.28 FPGA core
	cpu1 : entity work.cpu09
		port map(
			clk => not(cpuClock),
			rst => not resetLow,
			rw => n_WR,
			addr => cpuAddress,
			data_in => cpuDataIn,
			data_out => cpuDataOut,
			halt => '0',
			hold => '0',
			irq => '0',
			firq => '0',
			nmi => '0'
		); 
	
	-- ____________________________________________________________________________________
	-- BASIC ROM	
--	rom1 : entity work.M6809_EXT_BASIC_ROM -- 8KB BASIC
--	rom1 : entity work.M6809_CAMELFORTH_ROM -- Camelforth @ 0xE000
  rom1 : entity work.M6809_SIMON_ROM -- Buggy @ 0xE000
		port map(
			address => cpuAddress(12 downto 0),
			clock => i_CLOCK_50,
			q => basRomData
		);
	
	-- ____________________________________________________________________________________
	-- RAM GOES HERE
-- 	ram1: entity work.InternalRam4K
--		port map
--		(
--			address 	=> cpuAddress(11 downto 0),
--			clock 	=> i_CLOCK_50,
--			data 		=> cpuDataOut,
--			wren 		=> not(n_memWR or n_internalRamCS),
--			q 			=> internalRam1DataOut
--		);
			
	-- ____________________________________________________________________________________
	-- SDRAM GOES HERE
	sdram1: entity work.ExternalSdram
		port map
		(
			-- physical pins to memory device
			dram_addr 	=> dram_addr,
			dram_dq 		=> dram_dq,
			dram_cas_n 	=> dram_cas_n,
			dram_ras_n 	=> dram_ras_n,
			dram_we_n 	=> dram_we_n,
			dram_cs_n 	=> dram_cs_n,
			dram_clk 	=> dram_clk,
			dram_cke 	=> dram_cke,
			dram_ba_1 	=> dram_ba_1,
			dram_ba_0 	=> dram_ba_0,
			dram_udqm 	=> dram_udqm,
			dram_ldqm 	=> dram_ldqm,	
			
			-- interface to system
			reset 					=> not n_reset,	-- reset button
			i_CLOCK_50				=> i_CLOCK_50,
			cpuclk  					=> cpuClock,		-- generated clock 
			cpureset_n 				=> resetLow,		-- generated reset 

			-- interface to memory
			addr(15 downto 0)  	=> cpuAddress,				
			addr(21 downto 16) 	=> "000000",
			dram_match  			=> not dram_match,
			dati(7 downto 0)		=> sdramDataOut,
			dato(7 downto 0) 		=> cpuDataOut,
			control_dati 			=> n_WR,
			control_dato 			=> not n_WR
		);
	
	-- ____________________________________________________________________________________
	-- INPUT/OUTPUT DEVICES
	-- Grant's VGA driver
	-- Removed the Composite video output
	io1 : entity work.SBCTextDisplayRGB
		port map (
			n_reset => resetLow,
			clk => i_CLOCK_50,
			
			-- RGB CompVideo signals
			hSync => hSync,
			vSync => vSync,
			videoR0 => videoR0,
			videoR1 => videoR1,
			videoG0 => videoG0,
			videoG1 => videoG1,
			videoB0 => videoB0,
			videoB1 => videoB1,
			
			n_wr => n_interface1CS or cpuClock or n_WR,
			n_rd => n_interface1CS or cpuClock or (not n_WR),
			n_int => n_int1,
			regSel => cpuAddress(0),
			dataIn => cpuDataOut,
			dataOut => interface1DataOut,
			ps2clk => ps2Clk,
			ps2Data => ps2Data
		);
	
	-- Replaced Grant's bufferedUART with Neal Crook's version which uses clock enables instead of clock
	io2 : entity work.bufferedUART
		port map(
			clk => i_CLOCK_50,
			n_wr => n_interface2CS or cpuClock or n_WR,
			n_rd => n_interface2CS or cpuClock or (not n_WR),
			n_int => n_int2,
			regSel => cpuAddress(0),
			dataIn => cpuDataOut,
			dataOut => interface2DataOut,
			rxClkEn  => serialEn,
			txClkEn => serialEn,			
			rxd => rxd1,
			txd => txd1,
			n_cts => cts1,
			n_rts => rts1
		);
	
	-- ____________________________________________________________________________________
	-- MEMORY READ/WRITE LOGIC
--	n_memRD <= not(cpuClock) nand n_WR;
--	n_memWR <= not(cpuClock) nand (not n_WR);
	
	-- ____________________________________________________________________________________
	-- CHIP SELECTS
	n_basRomCS <= '0' when cpuAddress(15 downto 13) = "111" else '1'; --8K at top of memory
	n_interface1CS <= '0' when ((cpuAddress(15 downto 1) = "111111111101000" and serSelect = '1') or 
										 (cpuAddress(15 downto 1) = "111111111101001" and serSelect = '0')) else '1'; -- 2 bytes FFD0-FFD1
	n_interface2CS <= '0' when ((cpuAddress(15 downto 1) = "111111111101001" and serSelect = '1') or 
										 (cpuAddress(15 downto 1) = "111111111101000" and serSelect = '0')) else '1'; -- 2 bytes FFD2-FFD3
--	n_internalRamCS <= '0' when cpuAddress(15 downto 12) = "0000" else '1'; -- 4K at bottom of memory (0x0 to 0xfff)
--	dram_match      <= '0' when cpuAddress(15 downto 12) = "0001" else '1'; -- next 4K at bottom of memory (0x1000 to 0x1fff)
	dram_match 		<= not n_basRomCS;
	
	-- ____________________________________________________________________________________
	-- BUS ISOLATION
	-- Order matters since SRAM overlaps I/O chip selects
	cpuDataIn <=
		interface1DataOut 		when n_interface1CS = '0' 		else
		interface2DataOut 		when n_interface2CS = '0' 		else
		basRomData 					when n_basRomCS = '0'			else
		internalRam1DataOut 		when n_internalRamCS = '0' 	else
		sdramDataOut            when dram_match = '0'         else
		x"FF";
	
	-- ____________________________________________________________________________________
	-- SYSTEM CLOCKS
	
	-- Baud Rate CLOCK SIGNALS	
baud_div: process (serialCount_d, serialCount)
    begin
        serialCount_d <= serialCount + 2416;
    end process;

process (i_CLOCK_50)
	begin
		if rising_edge(i_CLOCK_50) then
        -- Enable for baud rate generator
        serialCount <= serialCount_d;
        if serialCount(15) = '0' and serialCount_d(15) = '1' then
            serialEn <= '1';
        else
            serialEn <= '0';
        end if;
		end if;
	end process;



end;
