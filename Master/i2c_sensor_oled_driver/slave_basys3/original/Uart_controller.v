`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/04 10:31:58
// Design Name: 
// Module Name: uart_controller
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


module uart_controller(
    input clk,
    input reset,
    input rx,
    
    // 센서 공유 레지스터 입력
    input [7:0] reg_temp,
    input [7:0] reg_humi,
    input [8:0] reg_dist,

    output tx
);

    wire [7:0] w_rx_data;
    wire       w_rx_done;
    wire       w_tx_busy;
    
    reg  [7:0] r_tx_data;
    reg        r_tx_start;

    // FSM 상태 정의
    localparam IDLE    = 2'd0;
    localparam PARSE   = 2'd1;
    localparam TRIGGER = 2'd2;
    localparam WAIT    = 2'd3;

    reg [1:0] state;

    // --- RX 명령 파서 및 TX 제어 FSM ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            r_tx_data  <= 8'd0;
            r_tx_start <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    r_tx_start <= 1'b0;
                    // PC에서 1바이트 명령 수신 완료 시
                    if (w_rx_done) begin
                        state <= PARSE;
                    end
                end

                PARSE: begin
                    // 이전 전송이 끝나 busy가 풀려있는지 확인 후 로드
                    if (!w_tx_busy) begin
                        case (w_rx_data)
                            "T", "t": begin
                                r_tx_data  <= reg_temp;
                                r_tx_start <= 1'b1;
                                state      <= TRIGGER;
                            end
                            "H", "h": begin
                                r_tx_data  <= reg_humi;
                                r_tx_start <= 1'b1;
                                state      <= TRIGGER;
                            end
                            "D", "d": begin
                                // 9비트 중 하위 8비트 우선 전송
                                r_tx_data  <= reg_dist[7:0];
                                r_tx_start <= 1'b1;
                                state      <= TRIGGER;
                            end
                            default: begin
                                state <= IDLE; // 알 수 없는 명령은 무시
                            end
                        endcase
                    end
                end

                TRIGGER: begin
                    // tx_start는 1클럭 펄스로 바로 내림
                    r_tx_start <= 1'b0;
                    state      <= WAIT;
                end

                WAIT: begin
                    // 송신이 끝나면 다시 수신 대기로 복귀
                    if (!w_tx_busy) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // --- 기존 UART TX / RX 모듈 인스턴스 ---
    uart_tx #(.BPS(9600)) u_uart_tx(
        .clk(clk), 
        .reset(reset),
        .tx_data(r_tx_data),
        .tx_start(r_tx_start),
        .tx(tx),
        .tx_busy(w_tx_busy)
    );

    uart_rx #(.BPS(9600)) u_uart_rx(
        .clk(clk), 
        .reset(reset),
        .rx(rx),        
        .data_out(w_rx_data),
        .rx_done(w_rx_done)
    );

endmodule
