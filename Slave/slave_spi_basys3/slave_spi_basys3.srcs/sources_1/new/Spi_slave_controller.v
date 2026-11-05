`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 11:44:50
// Design Name: 
// Module Name: Spi_slave_controller
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


module Spi_slave_controller(
    input clk,             
    input reset,           
    // SPI 인터페이스 포트 (총 4개)
    input      spi_sclk,   // 마스터로부터 받는 SPI 클록
    input      spi_mosi,   // 마스터 -> 슬레이브 데이터 입력
    output reg spi_miso,   // 슬레이브 -> 마스터 데이터 출력
    input      spi_cs,     // 칩 셀렉트 입력 (마스터가 나를 선택했는지 확인)
    
    // 센서(DHT11, 초음파 등) 데이터 연동을 위한 포트 (예시)
    input [7:0] sensor_data_in // 센서에서 읽어온 최신 측정값
    );
endmodule
