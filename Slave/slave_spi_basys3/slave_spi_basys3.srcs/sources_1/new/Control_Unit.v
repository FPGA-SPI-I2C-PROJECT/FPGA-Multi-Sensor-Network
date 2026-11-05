`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 11:22:49
// Design Name: 
// Module Name: Control_Unit
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


module Control_Unit(
    input clk,
    input reset,
    
    // 1. 센서 측정값 입력
    input [7:0] humidity,
    input [15:0] temperature,
    input [8:0] distance,
    
    // 2. UART RX (명령 수신부)
    input rx_done,
    input [7:0] rx_data,

    // 3. 상태 디버깅용 LED
    output [15:0] led,
    
    // 4. UART TX (데이터 송신부 - 수정 및 추가됨)
    input tx_busy,           // 추가: UART 모듈이 현재 데이터를 보내는 중인지(1) 대기 중인지(0) 확인
    output reg [7:0] tx_data,// 수정: 1비트 -> 8비트 (UART로 건네줄 1바이트 조각)
    output reg tx_req        // 추가: UART 모듈에게 "tx_data 전송 시작해!"라고 알리는 1클록 펄스
);
endmodule
