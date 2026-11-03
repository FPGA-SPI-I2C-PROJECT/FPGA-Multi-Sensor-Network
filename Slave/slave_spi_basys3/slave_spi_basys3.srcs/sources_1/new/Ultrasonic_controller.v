`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 11:19:08
// Design Name: 
// Module Name: Ultrasonic_controller
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


module Ultrasonic_controller(
    input clk,
    input reset,
    input echo,

    output trig,
    output [8:0] distance
    );

    ultrasonic_senser u_ultrasonic_senser(
        .clk(clk),
        .reset(reset),
        .start_trig(),
        .echo(echo),
        .trig(trig),
        .distance(distance)
    ); 

    
endmodule
