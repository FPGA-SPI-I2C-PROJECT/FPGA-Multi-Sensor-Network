`timescale 1ns / 1ps

// Uses the supplied uart_rx.v and uart_tx.v (100 MHz clock, 8N1).
module uart_controller_master #(
    parameter integer BPS = 9600
)(
    input wire clk, reset,
    input wire rx,
    output wire tx,
    input wire [1:0] mode_in,       // synchronized: 01=SPI, 10=I2C
    input wire master_busy,
    output reg request,            // one-clock pulse
    output reg [2:0] request_mask,  // {distance, humidity, temperature}
    output reg [1:0] request_mode,
    output reg reply_overflow      // sticky; cleared by reset
);
    localparam [1:0] R_OK=0, R_FORMAT=1, R_BUSY=2, R_MODE=3;
    localparam [7:0] CR=8'h0D, LF=8'h0A;

    (* ASYNC_REG = "TRUE" *) reg [1:0] rx_sync;
    wire [7:0] rx_data;
    wire rx_done, tx_busy;
    reg [7:0] tx_data;
    reg tx_start;

    // Rx Syncronization
    always @(posedge clk or posedge reset)
        if (reset) rx_sync <= 2'b11;
        else rx_sync <= {rx_sync[0], rx};

    uart_rx #(.BPS(BPS)) u_rx (
        .clk(clk), .reset(reset), .rx(rx_sync[1]),
        .data_out(rx_data), .rx_done(rx_done)
    );

    uart_tx #(.BPS(BPS)) u_tx (
        .clk(clk), .reset(reset), .tx_data(tx_data),
        .tx_start(tx_start), .tx(tx), .tx_busy(tx_busy)
    );

    reg [7:0] c0, c1, c2;
    reg [2:0] length;              // saturates at 4: too long
    reg last_cr;

    wire line_end = rx_done && ((rx_data == CR) || ((rx_data == LF) && !last_cr));  // rx_done이 1이 되고, 마지막 rx_data가 CR이거나 rx_data가 CR은 아니어도 LF이면 문자열을 line을 모두 보냇다, 

    function [2:0] decode_mask; // 원하는 데이터를 요청하는 mask 생성
        input [2:0] n;
        input [7:0] a, b, c;
        begin
            decode_mask = 3'b000;

            case (n)
                1: case (a)
                    "T": decode_mask = 3'b001;
                    "H": decode_mask = 3'b010;
                    "D": decode_mask = 3'b100;
                    default: decode_mask = 3'b000;
                endcase

                2: case ({a,b})
                    "TH": decode_mask = 3'b011;
                    "TD": decode_mask = 3'b101;
                    "HD": decode_mask = 3'b110;
                    default: decode_mask = 3'b000;
                endcase

                3: if ((a == "T" || a == "X") &&
                       (b == "H" || b == "X") &&
                       (c == "D" || c == "X"))
                    decode_mask = {c == "D", b == "H", a == "T"};

                default: decode_mask = 3'b000;
            endcase
        end
    endfunction

    wire [2:0] decoded = decode_mask(length, c0, c1, c2);

    wire [1:0] response = (decoded == 0) ? R_FORMAT :
        ((mode_in != 2'b01) && (mode_in != 2'b10)) ? R_MODE :
        (master_busy || request) ? R_BUSY : R_OK;

    // Reply FIFO: 16 waiting replies plus one active reply.
    reg [1:0] reply_fifo [0:15];
    reg [3:0] wr_ptr, rd_ptr;
    reg [4:0] reply_count;
    reg reply_active;
    reg [1:0] active_reply;
    reg [3:0] char_index;

    wire pop_reply = !reply_active && (reply_count != 0);
    wire reply_space = (reply_count < 16) || pop_reply;
    wire push_reply = line_end && reply_space;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            c0 <= 0;
            c1 <= 0;
            c2 <= 0;
            length <= 0;
            last_cr <= 0;

            request <= 0;
            request_mask <= 0;
            request_mode <= 0;
            reply_overflow <= 0;
        end else begin
            request <= 1'b0;

            if (rx_done) begin
                last_cr <= (rx_data == CR);

                if (rx_data == CR || rx_data == LF) begin
                    if (line_end) begin
                        length <= 0;
                        c0 <= 0;
                        c1 <= 0;
                        c2 <= 0;

                        if (!reply_space)
                            reply_overflow <= 1'b1;
                        else if (response == R_OK) begin
                            request <= 1'b1;
                            request_mask <= decoded;
                            request_mode <= mode_in;
                        end
                    end
                end else begin
                    // Clearing bit 5 maps t/h/d/x to T/H/D/X.
                    case (length)
                        0: c0 <= rx_data & 8'hDF;
                        1: c1 <= rx_data & 8'hDF;
                        2: c2 <= rx_data & 8'hDF;
                        default: begin end
                    endcase

                    if (length < 4)
                        length <= length + 1'b1;
                end
            end
        end
    end

    function [3:0] reply_length;
        input [1:0] kind;
        begin
            case (kind)
                R_OK:     reply_length = 4;
                R_FORMAT: reply_length = 12;
                default:  reply_length = 10;
            endcase
        end
    endfunction

    function [7:0] reply_char;
        input [1:0] kind;
        input [3:0] index;
        reg [95:0] text;
        begin
            case (kind)
                R_OK:
                    text = {"OK", CR, LF, 64'b0};

                R_FORMAT:
                    text = {"ERR FORMAT", CR, LF};

                R_BUSY:
                    text = {"ERR BUSY", CR, LF, 16'b0};

                default:
                    text = {"ERR MODE", CR, LF, 16'b0};
            endcase

            reply_char = text[95 - index*8 -: 8];
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            reply_count <= 0;

            reply_active <= 0;
            active_reply <= R_OK;
            char_index <= 0;

            tx_start <= 0;
            tx_data <= 0;
        end else begin
            tx_start <= 1'b0;

            if (push_reply) begin
                reply_fifo[wr_ptr] <= response;
                wr_ptr <= wr_ptr + 1'b1;
            end

            if (pop_reply) begin
                active_reply <= reply_fifo[rd_ptr];
                rd_ptr <= rd_ptr + 1'b1;
                char_index <= 0;
                reply_active <= 1'b1;
            end

            case ({push_reply, pop_reply})
                2'b10: reply_count <= reply_count + 1'b1;
                2'b01: reply_count <= reply_count - 1'b1;
                default: begin end
            endcase

            // tx_start guard prevents resubmitting before tx_busy rises.
            if (reply_active && !tx_busy && !tx_start) begin
                tx_data <= reply_char(active_reply, char_index);
                tx_start <= 1'b1;

                if (char_index == reply_length(active_reply)-1'b1)
                    reply_active <= 1'b0;
                else
                    char_index <= char_index + 1'b1;
            end
        end
    end
endmodule