`timescale 1ns / 1ps

module uart_controller(
    input clk,
    input reset,
    input rx,
    
    // 센서 공유 레지스터 입력
    input [7:0] reg_temp,
    input [7:0] reg_humi,
    input [7:0] reg_temp_dec,
    input [7:0] reg_humi_dec,
    input [8:0] reg_dist,

    output tx,
    output rx_valid
);

    wire [7:0] w_rx_data;
    wire       w_rx_done;
    wire       w_tx_busy;
    
    reg  [7:0] r_tx_data;
    reg        r_tx_start;

    // FSM 상태 정의: 버퍼 방식으로 간소화
    localparam IDLE     = 2'd0;
    localparam PARSE    = 2'd1;
    localparam SEND_BUF = 2'd2;
    localparam WAIT_BUF = 2'd3;

    reg [1:0] state;

    // 변환기 연결 레지스터 및 와이어
    reg  [8:0] r_bin_target;
    wire [7:0] w_ascii_hun;
    wire [7:0] w_ascii_ten;
    wire [7:0] w_ascii_one;

    // [추가] 소수부 데이터 레지스터
    reg  [7:0] r_dec_target;

    // 송신 버퍼 및 인덱스 (한글 2글자 + 공백 + 숫자 + 개행 = 약 15바이트)
    reg [7:0] tx_buf [0:31];
    reg [5:0] tx_len;
    reg [5:0] tx_idx;

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

    bin2ascii u_bin2ascii (
        .bin_val(r_bin_target),
        .ascii_hun(w_ascii_hun),
        .ascii_ten(w_ascii_ten),
        .ascii_one(w_ascii_one)
    );

    assign rx_valid = w_rx_done;

    // --- RX 명령 파서 및 버퍼 직렬 TX FSM ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            r_tx_data    <= 8'd0;
            r_tx_start   <= 1'b0;
            r_bin_target <= 9'd0;
            r_dec_target <= 8'd0;
            tx_len       <= 6'd0;
            tx_idx       <= 6'd0;
        end else begin
            case (state)
                IDLE: begin
                    r_tx_start <= 1'b0;
                    if (w_rx_done) begin
                        state <= PARSE;
                        // 수신 명령어에 따라 bin2ascii 입력값 즉시 설정
                        case (w_rx_data)
                            "T", "t": begin
                                r_bin_target <= {1'b0, reg_temp};
                                r_dec_target <= reg_temp_dec;
                            end
                            "H", "h": begin
                                r_bin_target <= {1'b0, reg_humi};
                                r_dec_target <= reg_humi_dec;
                            end
                            "D", "d": begin
                                r_bin_target <= reg_dist;
                            end
                        endcase
                    end
                end

                PARSE: begin
                    if (!w_tx_busy) begin
                        tx_idx <= 6'd0;

                        case (w_rx_data)
                            // "온도 34.5\r\n"
                            "T", "t": begin
                                tx_buf[0]  <= 8'hBF; // '온' (CP949 1바이트)
                                tx_buf[1]  <= 8'hC2; // '온' (CP949 2바이트)
                                tx_buf[2]  <= 8'hB5; // '도'
                                tx_buf[3]  <= 8'hB5;
                                tx_buf[4]  <= 8'h20; // ' ' (공백)
                                tx_buf[5]  <= w_ascii_ten;
                                tx_buf[6]  <= w_ascii_one;
                                tx_buf[7]  <= 8'h2E; // '.'
                                tx_buf[8]  <= {4'h3, r_dec_target[3:0]};
                                tx_buf[9]  <= 8'h0D; // \r
                                tx_buf[10] <= 8'h0A; // \n
                                tx_len     <= 6'd11;
                                state      <= SEND_BUF;
                            end

                            // "습도 44.5\r\n"
                            "H", "h": begin
                                tx_buf[0]  <= 8'hBD; // '습'
                                tx_buf[1]  <= 8'hC0;
                                tx_buf[2]  <= 8'hB5; // '도'
                                tx_buf[3]  <= 8'hB5;
                                tx_buf[4]  <= 8'h20; // ' ' (공백)
                                tx_buf[5]  <= w_ascii_ten;
                                tx_buf[6]  <= w_ascii_one;
                                tx_buf[7]  <= 8'h2E; // '.'
                                tx_buf[8]  <= {4'h3, r_dec_target[3:0]};
                                tx_buf[9]  <= 8'h0D; // \r
                                tx_buf[10] <= 8'h0A; // \n
                                tx_len     <= 6'd11;
                                state      <= SEND_BUF;
                            end

                            // "거리 025\r\n"
                            "D", "d": begin
                                tx_buf[0]  <= 8'hB0; // '거'
                                tx_buf[1]  <= 8'hC5;
                                tx_buf[2]  <= 8'hB8; // '리'
                                tx_buf[3]  <= 8'hAE;
                                tx_buf[4]  <= 8'h20; // ' ' (공백)
                                tx_buf[5]  <= w_ascii_hun;
                                tx_buf[6]  <= w_ascii_ten;
                                tx_buf[7]  <= w_ascii_one;
                                tx_buf[8]  <= 8'h0D; // \r
                                tx_buf[9]  <= 8'h0A; // \n
                                tx_len     <= 6'd10;
                                state      <= SEND_BUF;
                            end

                            default: begin
                                state <= IDLE;
                            end
                        endcase
                    end
                end

                // 버퍼 1바이트 전송
                SEND_BUF: begin
                    r_tx_data  <= tx_buf[tx_idx];
                    r_tx_start <= 1'b1;
                    state      <= WAIT_BUF;
                end

                // 전송 대기 및 포인터 전진
                WAIT_BUF: begin
                    r_tx_start <= 1'b0;
                    if (!w_tx_busy && !r_tx_start) begin
                        if (tx_idx + 1 >= tx_len) begin
                            state <= IDLE;
                        end else begin
                            tx_idx <= tx_idx + 1;
                            state  <= SEND_BUF;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule