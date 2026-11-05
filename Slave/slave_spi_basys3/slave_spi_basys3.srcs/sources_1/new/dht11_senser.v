`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 10:53:05
// Design Name: 
// Module Name: dht11_senser
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


module dht11_senser(
    input clk,
    input io_mode, // 1: 입력모드, 0: 출력모드
    input o_data, // 출력할 데이터
    output i_data, // 읽은 데이터
    inout dht11_data // 실제 핀
    );
    assign dht11_data = io_mode ? 1'bz : o_data;

    assign i_data = dht11_data; // 입력 모드일 때 dht11_data 값을 읽음
endmodule
