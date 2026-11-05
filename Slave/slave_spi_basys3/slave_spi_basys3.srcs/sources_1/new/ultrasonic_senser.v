`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 10:52:35
// Design Name: 
// Module Name: ultrasonic_senser
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ultrasonic_senser(
    input clk,
    input reset,
    input start_trig,
    input echo,
    
    output reg trig,
    output reg [8:0] distance
    );  
endmodule
