`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 10:53:25
// Design Name: 
// Module Name: top_slave
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


module top_slave(
    input clk,
    input reset,
    input echo,
    input RsRx,

    output trig,
    output RsTx,
    output [15:0] led,
    output rx_valid,

    inout dht11_data,

    //spi 통신
    input spi_sclk, //외부 클록 수신
    input spi_mosi, //데이터 수신
    input spi_cs,   //활성화 신호 수신
    output spi_miso, //데이터 송신

    // I2C 통신 추가
    input i2c_scl,
    inout i2c_sda,

    output test_uart_rx, test_uart_tx

    );
    wire dht_start, ultra_start, dht_done, ultra_done, dht_error;
    wire [7:0] measured_temp, measured_humi, reg_temp, reg_humi;
    wire [8:0] measured_dist, reg_dist;
    wire spi_selected, spi_done, spi_error;
    wire i2c_selected, i2c_done, i2c_error;
    wire [7:0] last_command;
    reg spi_seen, i2c_seen;


    reg [7:0] r_temp;
    reg [7:0] r_humi;
    reg [8:0] r_dist;


    wire [7:0] w_dht_temp, w_dht_humi;
    wire [7:0] w_dht_temp_dec, w_dht_humi_dec;
    wire       w_dht_done;
    wire       w_dht11_err;

    wire [8:0] w_ultra_dist;
    wire       w_ultra_done;

    wire [7:0] w_out_dht_temp, w_out_dht_humi;
    wire [7:0] w_out_dht_temp_dec, w_out_dht_humi_dec;
    wire [8:0] w_out_ultra_dist;

    wire w_dht_start, w_ultra_start;

    
    sensor_trigger_generator u_trigger_genergenerator (
        .clk(clk),
        .reset(reset),
        .ultra_start_tick(w_ultra_start),
        .dht_start_tick(w_dht_start)
    );

    dht11_sensor u_dht11_sensor(
        .clk(clk),
        .reset(reset),
        .start(w_dht_start),      
        .dht11_data(dht11_data), 
        .humidity(w_dht_humi),   
        .temperature(w_dht_temp),
        .humidity_dec(w_dht_humi_dec),   
        .temperature_dec(w_dht_temp_dec),        
        .done(w_dht_done),       
        .err(w_dht11_err)         
    );

    ultrasonic_sensor u_ultrasonic_sensor(
        .clk(clk),
        .reset(reset),
        .start_trig(w_ultra_start),
        .trig(trig),
        .echo(echo),
        .distance(w_ultra_dist),
        .done(w_ultra_done)
    );

    sensor_reg_bank u_reg_bank (
        .clk(clk), 
        .reset(reset),
        .dht_done(w_dht_done),
        .dht_temp(w_dht_temp),
        .dht_humi(w_dht_humi),
        .dht_temp_dec(w_dht_temp_dec),
        .dht_humi_dec(w_dht_humi_dec),
        .ultra_done(w_ultra_done),
        .ultra_dist(w_ultra_dist),

        .reg_temp(w_out_dht_temp),
        .reg_humi(w_out_dht_humi),
        .reg_temp_dec(w_out_dht_temp_dec),
        .reg_humi_dec(w_out_dht_humi_dec),
        .reg_dist(w_out_ultra_dist)
    );


    uart_controller u_uart_controller(
        .clk(clk),
        .reset(reset),
        .rx(RsRx),
        .reg_temp(w_out_dht_temp),
        .reg_humi(w_out_dht_humi),
        .reg_temp_dec(w_out_dht_temp_dec),
        .reg_humi_dec(w_out_dht_humi_dec),
        .reg_dist(w_out_ultra_dist),
        .rx_valid(rx_valid),
        .tx(RsTx)
    );

    assign test_uart_rx = RsRx;
    assign test_uart_tx = RsTx;

    spi_sensor_slave u_spi_sensor_slave (
        .clk(clk),
        .reset(reset),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs),              // Active Low CS 신호 연결
        .spi_miso(spi_miso),
        .reg_temp(w_out_dht_temp),      // 레지스터 뱅크의 온도 출력 연결 일단 정수부문만
        .reg_humi(w_out_dht_humi),      // 레지스터 뱅크의 습도 출력 연결
        .reg_dist(w_out_ultra_dist),    // 레지스터 뱅크의 거리 출력 연결
        .selected(spi_selected),
        .transaction_done(spi_done),
        .command_error(spi_error),
        .last_command(last_command)
    );

    i2c_sensor_slave #(
        .SLAVE_ADDR(7'h42),
        .CLK_HZ(100_000_000),
        .IDLE_TIMEOUT_MS(25)
    ) u_i2c_sensor_slave (
        .clk(clk),
        .reset(reset),
        .scl(i2c_scl),
        .sda(i2c_sda),
        
        // 레지스터 뱅크의 출력 데이터를 공유 일단 정수부문만
        .reg_temp(w_out_dht_temp),
        .reg_humi(w_out_dht_humi),
        .reg_dist(w_out_ultra_dist),
        
        // 상태 출력
        .selected(i2c_selected),
        .transaction_done(i2c_done),
        .command_error(i2c_error)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            spi_seen <= 1'b0;
            i2c_seen <= 1'b0;
        end else begin
            if (spi_done) spi_seen <= 1'b1;
            if (i2c_done) i2c_seen <= 1'b1;
        end
    end

    // led 16비트 매핑: 
    // [15] DHT에러 | [14:12] SPI상태 | [11:9] I2C상태 | [8:0] 초음파 거리(9비트)
    assign led = {
        w_dht11_err, 
        spi_error, spi_selected, spi_seen, 
        i2c_error, i2c_selected, i2c_seen, 
        w_out_ultra_dist
    };


endmodule
