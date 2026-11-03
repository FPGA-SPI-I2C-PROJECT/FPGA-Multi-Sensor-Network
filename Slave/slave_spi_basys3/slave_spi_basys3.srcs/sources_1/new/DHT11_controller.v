`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 17:29:14
// Design Name: 
// Module Name: dht11_controller
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


module dht11_controller (
    input  wire        clk,        // 100MHz
    input  wire        reset,
    input  wire        start,      // 측정 시작 트리거 (1클록 펄스)
    inout  wire        dht11_data, // 실제 센서 핀 (외장 풀업 저항 필요)

    output reg  [7:0]  humidity,   // 습도 정수부
    output reg  [7:0]  temperature,// 온도 정수부
    output reg         done,       // 측정 완료 펄스 (1클록)
    output reg         err         // 체크섬 오류 또는 타임아웃
);

    // 100MHz 기준 1us = 100 클록
    localparam CLK_PER_US = 100;

    // FSM 상태 정의
    localparam S_IDLE        = 4'd0;
    localparam S_START_LOW   = 4'd1; // 18ms Low
    localparam S_START_HIGH  = 4'd2; // 30us High (버스 릴리즈)
    localparam S_RESP_LOW    = 4'd3; // 센서 응답 Low (80us) 대기
    localparam S_RESP_HIGH   = 4'd4; // 센서 응답 High (80us) 대기
    localparam S_BIT_LOW     = 4'd5; // 데이터 비트 시작 Low (50us) 대기
    localparam S_BIT_HIGH    = 4'd6; // 데이터 비트 High 길이 측정 (28us / 70us)
    localparam S_CHECK       = 4'd7; // 체크섬 검사

    reg [3:0]  state;
    reg [31:0] clk_cnt;
    reg [19:0] us_cnt;
    reg        us_tick;

    // Inout 핀 제어 레지스터
    reg        io_mode; // 1: 입력 (High-Z), 0: 출력
    reg        o_data;
    wire       i_data;

    // Tri-state Buffer 제어
    assign dht11_data = io_mode ? 1'bz : o_data;
    assign i_data     = dht11_data;

    // 핀 입력 동기화 (메타스테이빌리티 방지)
    reg [2:0] dht_sync;
    always @(posedge clk or posedge reset) begin
        if (reset) dht_sync <= 3'b111;
        else       dht_sync <= {dht_sync[1:0], i_data};
    end
    wire dht_in = dht_sync[2];

    // 1us 펄스 생성기
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt <= 0;
            us_tick <= 0;
        end else if (clk_cnt >= CLK_PER_US - 1) begin
            clk_cnt <= 0;
            us_tick <= 1'b1;
        end else begin
            clk_cnt <= clk_cnt + 1;
            us_tick <= 1'b0;
        end
    end

    // 수신 데이터 및 비트 카운터
    reg [39:0] rx_shift;
    reg [5:0]  bit_idx;
    reg [15:0] high_cnt_us;

    // FSM 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= S_IDLE;
            io_mode     <= 1'b1; // 기본은 High-Z (풀업 유지)
            o_data      <= 1'b1;
            us_cnt      <= 0;
            bit_idx     <= 0;
            high_cnt_us <= 0;
            humidity    <= 0;
            temperature <= 0;
            done        <= 0;
            err         <= 0;
        end else begin
            done <= 0;
            err  <= 0;

            case (state)
                S_IDLE: begin
                    io_mode <= 1'b1;
                    o_data  <= 1'b1;
                    us_cnt  <= 0;
                    if (start) begin
                        io_mode <= 1'b0; // 출력 모드 전환
                        o_data  <= 1'b0; // 라인 Low 구동
                        state   <= S_START_LOW;
                    end
                end

                // 18ms (18000us) 동안 라인을 Low로 유지
                S_START_LOW: begin
                    if (us_tick) begin
                        if (us_cnt >= 20'd18000) begin
                            us_cnt  <= 0;
                            o_data  <= 1'b1; // 라인 High
                            state   <= S_START_HIGH;
                        end else begin
                            us_cnt <= us_cnt + 1;
                        end
                    end
                end

                // 30us 동안 High 유지 후 센서에게 제어권 넘김
                S_START_HIGH: begin
                    if (us_tick) begin
                        if (us_cnt >= 20'd30) begin
                            us_cnt  <= 0;
                            io_mode <= 1'b1; // 입력 모드로 전환 (풀업에 의해 High)
                            state   <= S_RESP_LOW;
                        end else begin
                            us_cnt <= us_cnt + 1;
                        end
                    end
                end

                // 센서의 Low 응답 대기 (최대 100us 타임아웃)
                S_RESP_LOW: begin
                    if (dht_in == 1'b0) begin
                        us_cnt <= 0;
                        state  <= S_RESP_HIGH;
                    end else if (us_tick) begin
                        if (us_cnt >= 20'd100) begin // 타임아웃 에러
                            err   <= 1'b1;
                            state <= S_IDLE;
                        end else begin
                            us_cnt <= us_cnt + 1;
                        end
                    end
                end

                // 센서의 High 응답 대기 (Low가 끝나고 High로 올라가는 시점)
                S_RESP_HIGH: begin
                    if (dht_in == 1'b1) begin
                        us_cnt  <= 0;
                        bit_idx <= 0;
                        state   <= S_BIT_LOW;
                    end
                end

                // 각 비트의 50us Low 구간 통과 대기
                S_BIT_LOW: begin
                    if (dht_in == 1'b1) begin // High 시작 지점
                        high_cnt_us <= 0;
                        state       <= S_BIT_HIGH;
                    end
                end

                // High 유지 시간 측정 (길이에 따라 0 또는 1 판정)
                S_BIT_HIGH: begin
                    if (dht_in == 1'b0) begin // High 종료 시점
                        // 40us보다 길면 1, 짧으면 0
                        rx_shift <= {rx_shift[38:0], (high_cnt_us > 16'd40) ? 1'b1 : 1'b0};
                        
                        if (bit_idx == 6'd39) begin
                            state <= S_CHECK;
                        end else begin
                            bit_idx <= bit_idx + 1;
                            state   <= S_BIT_LOW;
                        end
                    end else if (us_tick) begin
                        high_cnt_us <= high_cnt_us + 1;
                        if (high_cnt_us >= 16'd150) begin // 비정상 신호 타임아웃
                            err   <= 1'b1;
                            state <= S_IDLE;
                        end
                    end
                end

                // 체크섬 검증: [39:32] + [31:24] + [23:16] + [15:8] == [7:0]
                S_CHECK: begin
                    if ((rx_shift[39:32] + rx_shift[31:24] + rx_shift[23:16] + rx_shift[15:8]) == rx_shift[7:0]) begin
                        humidity    <= rx_shift[39:32];
                        temperature <= rx_shift[23:16];
                        done        <= 1'b1;
                    end else begin
                        err <= 1'b1; // 체크섬 불일치
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
