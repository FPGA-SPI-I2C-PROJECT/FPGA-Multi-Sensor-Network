`timescale 1ns / 1ps

module uart_rx # (
    parameter BPS = 9600
) (
    input clk,
    input reset,
    input rx,
    output reg [7:0] data_out,
    output reg rx_done  // 수신 완료
    );
    
    localparam S_IDLE = 2'b00;
    localparam S_START_BIT = 2'b01;
    localparam S_DATA_8BITS = 2'b10;
    localparam S_STOP_BIT = 2'b11;

    // 9600 * 16 = 153,600
    // 100_000_000 Hz / 153,600 = 651 ns (651 clk 주기로 sampling)
    // 100_000_000 : 1 초당 clk tick 횟수
    // 9600 : 1초당 9600 bit를 보냄.
    // 1 bit를 읽는 데 필요한 clk Tick = 1 초 동안 보내는 clk tick [Hz] / 1초 동안 보내는 bit 수 [Hz] = 100_000_000 / 9600 [Hz]
    // 1 bit를 16 번 over sampling 한다 = 1초당 읽어야하는 bit 수가 16배가 된다 => BPS가 16배가 되는 것과 같다.
    // 1bit를 16번 over sampling 할 때 필요한 ckl tick 수 = 100_000_000 / (9600 * 16) = 약 651 개
    // 651개 clk의 period = 10 ns * 651 = 6510 ns = 6.51 us
    
    localparam DIV = 100_000_000 / (BPS * 16);  // 16 oversampling

    reg [1:0] rx_state;         // state: IDLE START DATA_BITS STOP_BIT
    reg [3:0] bit_cnt;          // r_data_reg에 들어갈 index 값
    reg [7:0] data_reg;         // rx 포트로부터 들어온 bit를 담을 그릇
    reg [15:0] baud_cnt;        // 651 ns: 9600 x 16 오버샘플링 (16) cnt 변수
    reg baud_tick;              // 651 ns 마다 tick 발생
    reg [3:0] baud_tick_cnt;    // 16개 오버샘플링 값 count

    // 1clk 10ns 651 clk => 6.51 us
    // 1. 651 us tick을 생성하는 logic
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end
        
        else begin
            if(baud_cnt >= DIV - 1) begin
                baud_cnt <= 0;
                baud_tick <= 1'b1;
            end
            else begin
                baud_cnt <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    // 2. rx_bit을 수신하는 FSM
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            rx_state <= S_IDLE;
            bit_cnt <= 4'd0;
            data_reg <= 8'b0;
            baud_tick_cnt <= 4'd0;
            data_out <= 8'd0;
            rx_done <= 1'b0;
        end

        else begin
            case(rx_state)
                S_IDLE: begin
                    rx_done <= 1'b0;
                    if(!rx) begin
                        rx_state <= S_START_BIT;
                        baud_tick_cnt <= 4'd0;
                    end
                end
                S_START_BIT: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd7) begin
                            rx_state <= S_DATA_8BITS;
                            baud_tick_cnt <= 4'd0;
                            bit_cnt <= 4'd0;
                        end
                    end
                end
                S_DATA_8BITS: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd15) begin
                            data_reg[bit_cnt] <= rx;
                            baud_tick_cnt <= 4'd0;

                            if(bit_cnt >= 4'd7) begin
                                rx_state <= S_STOP_BIT;
                                bit_cnt <= 4'd0;
                            end
                            else bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
                S_STOP_BIT: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd15) begin
                            rx_state <= S_IDLE;
                            baud_tick_cnt <= 4'd0;
                            data_out <= data_reg;
                            rx_done <= 1'b1;
                        end
                    end
                end
                default: rx_state <= S_IDLE;
            endcase
        end
    end
endmodule
