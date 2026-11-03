`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 11:28:33
// Design Name: 
// Module Name: Uart_controller
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


module Uart_controller(
    input clk,
    input reset,
    input rx,

    output tx,
    output rx_done,
    output reg [7:0] rx_data
    );

    uart_tx #(.BPS(9600)) u_uart_tx(
        .clk(clk), 
        .reset(reset),
        .tx_data(),
        .tx_start(),
        .tx(tx),
        .tx_busy()
    );

    uart_rx #(.BPS(9600)) u_uart_rx(
        .clk(clk), 
        .reset(reset),
        .rx(rx),        
        .data_out(rx_data),
        .rx_done(rx_done)
    );
endmodule
