----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/19/2026 02:28:09 PM
-- Design Name: 
-- Module Name: toggle2pulse_tb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity toggle2pulse_tb is
end toggle2pulse_tb;

architecture Behavioral of toggle2pulse_tb is

    -- Component declaration
    component toggle2pulse is
        Generic ( pulse_width :     integer := 4 );
        Port (    toggle      : in  STD_LOGIC;
                  pulse       : out STD_LOGIC;
                  clk         : in  STD_LOGIC;
                  rst         : in  STD_LOGIC);
    end component;

    -- Constants
    constant CLK_PERIOD   : time    := 10 ns;
    constant PULSE_WIDTH  : integer := 4;

    -- Signals
    signal clk    : STD_LOGIC := '0';
    signal rst    : STD_LOGIC := '0';
    signal toggle : STD_LOGIC := '0';
    signal pulse  : STD_LOGIC;

    -- Simulation control
    signal sim_done : boolean := false;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: toggle2pulse
        generic map (
            pulse_width => PULSE_WIDTH
        )
        port map (
            toggle => toggle,
            pulse  => pulse,
            clk    => clk,
            rst    => rst
        );

    -- Clock generation process
    clk_process: process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus process
    stim_process: process
    begin
        -- Initialize with reset
        rst <= '1';
        toggle <= '0';
        wait for CLK_PERIOD * 5;
        
        -- Release reset
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 1: Toggle from 0 to 1
        report "Test 1: Toggle 0 -> 1";
        toggle <= '1';
        wait for CLK_PERIOD;
        
        -- Wait for pulse to complete (pulse_width cycles)
        wait for CLK_PERIOD * (PULSE_WIDTH + 2);
        
        -- Verify pulse is low after pulse_width cycles
        assert pulse = '0'
            report "Test 1 Failed: Pulse should be low after pulse_width cycles"
            severity error;
        
        -- Test 2: Toggle from 1 to 0
        report "Test 2: Toggle 1 -> 0";
        toggle <= '0';
        wait for CLK_PERIOD;
        
        -- Wait for pulse to complete
        wait for CLK_PERIOD * (PULSE_WIDTH + 2);
        
        -- Verify pulse is low
        assert pulse = '0'
            report "Test 2 Failed: Pulse should be low after pulse_width cycles"
            severity error;
        
        -- Test 3: Multiple rapid toggles
        report "Test 3: Multiple toggles";
        toggle <= '1';
        wait for CLK_PERIOD * 2;
        toggle <= '0';
        wait for CLK_PERIOD * 2;
        toggle <= '1';
        wait for CLK_PERIOD * (PULSE_WIDTH + 2);
        
        -- Test 4: Reset during pulse
        report "Test 4: Reset during pulse";
        toggle <= '0';
        wait for CLK_PERIOD * 2;
        rst <= '1';
        wait for CLK_PERIOD * 2;
        
        -- Verify pulse is low during reset
        assert pulse = '0'
            report "Test 4 Failed: Pulse should be low during reset"
            severity error;
        
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        -- Test 5: Toggle after reset
        report "Test 5: Toggle after reset";
        toggle <= '1';
        wait for CLK_PERIOD;
        
        -- Verify pulse is high
        wait for CLK_PERIOD;
        assert pulse = '1'
            report "Test 5 Failed: Pulse should be high after toggle"
            severity error;
        
        wait for CLK_PERIOD * (PULSE_WIDTH + 2);
        
        -- End simulation
        report "All tests completed";
        sim_done <= true;
        wait;
    end process;

end Behavioral;
