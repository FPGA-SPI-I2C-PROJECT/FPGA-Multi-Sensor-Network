`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 11:19:08
// Design Name: 
// Module Name: DHT11_controller
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


module DHT11_controller(
    input clk,
    input reset,
    input dht11_data,

    output [7:0] humidity,
    output [15:0] temperature
    );

    // dht11_senser u_dht11_senser(
    //     .clk(clk),
    //     .io_mode(), 
    //     .o_data(), 
    //     .i_data(), 
    //     .dht11_data(dht11_data) 
    // );
    
endmodule
