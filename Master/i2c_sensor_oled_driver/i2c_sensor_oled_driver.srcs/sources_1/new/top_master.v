`timescale 1ns / 1ps
// Basys3 + 4-pin SSD1306 I2C module with onboard power-on reset.
module top_master #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter integer OLED_HEIGHT = 32, // 32 or 64; match the actual panel
    parameter [6:0] OLED_ADDR = 7'h3C,
    parameter integer POWERUP_MS = 100,
    parameter integer TIMEOUT_MS = 250
)(
    input wire clk,
    input wire btnC,
    inout wire oled_sda,
    inout wire oled_scl,
    output wire [15:0] led
);
    // FPGA initialization holds reset at configuration; synchronous release.
    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_pipe = 4'b1111;
    always @(posedge clk or posedge btnC)
        if (btnC) reset_pipe <= 4'b1111;
        else reset_pipe <= {reset_pipe[2:0],1'b0};
        
    wire reset = reset_pipe[3];
    localparam integer WAIT_CYCLES = (CLK_HZ / 1000) * POWERUP_MS;
    localparam [10:0] FRAME_LENGTH = 1 + 128 * (OLED_HEIGHT / 8);
    localparam [7:0] MUX = OLED_HEIGHT - 1;
    localparam [7:0] COM_CONFIG = (OLED_HEIGHT == 64) ? 8'h12 : 8'h02;
    localparam [7:0] LAST_PAGE = OLED_HEIGHT / 8 - 1;
    localparam [2:0] WAIT_POWER=0, LAUNCH=1, WAIT_PACKET=2, FINISH=3, ERROR=4;
    reg [2:0] state;
    reg [1:0] packet;
    reg [31:0] wait_count;
    reg start;
    reg [10:0] length;
    reg [7:0] data;
    wire [10:0] index;
    wire busy, done, nack, timeout_error;
    reg pass, fail, nack_seen, timeout_seen;

    i2c_write_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(I2C_HZ),
        .TIMEOUT_MS(TIMEOUT_MS)) master (
        .clk(clk), .reset(reset), .start(start), .address(OLED_ADDR),
        .length(length), .byte_index(index), .byte_data(data),
        .busy(busy), .done(done), .nack(nack), .timeout_error(timeout_error),
        .sda(oled_sda), .scl(oled_scl)
    );

    // 5x7 lowercase glyphs, column-major, bit 0 at top; one blank column.
    // Pixels go in page 0, columns 0..17. Everything else is cleared.
    function [7:0] glyph;
        input [10:0] x;
        begin
            case (x)
                 0: glyph=8'h20;  1: glyph=8'h54;  2: glyph=8'h54;
                 3: glyph=8'h54;  4: glyph=8'h78;  5: glyph=8'h00; // a
                 6: glyph=8'h7F;  7: glyph=8'h48;  8: glyph=8'h44;
                 9: glyph=8'h44; 10: glyph=8'h38; 11: glyph=8'h00; // b
                12: glyph=8'h38; 13: glyph=8'h44; 14: glyph=8'h44;
                15: glyph=8'h44; 16: glyph=8'h20; 17: glyph=8'h00; // c
                default: glyph=8'h00;
            endcase
        end
    endfunction

    // Packet 0: configure with display OFF and horizontal addressing.
    // Packet 1: set full-screen window. Packet 2: entire frame with abc.
    // Packet 3: display ON, avoiding random power-up RAM on screen.
    always @* begin
        data = 8'h00;
        length = 11'd2;
        case (packet)
            0: begin
                length = 11'd26; // control + 25 command/argument bytes
                case (index)
                     0: data=8'h00; // Co=0, D/C#=0: following bytes are commands
                     1: data=8'hAE; // display off
                     2: data=8'hD5;  3: data=8'h80; // display clock
                     4: data=8'hA8;  5: data=MUX;
                     6: data=8'hD3;  7: data=8'h00; // offset
                     8: data=8'h40; // start line 0
                     9: data=8'h8D; 10: data=8'h14; // internal charge pump
                    11: data=8'h20; 12: data=8'h00; // horizontal mode
                    13: data=8'hA1; 14: data=8'hC8; // orientation
                    15: data=8'hDA; 16: data=COM_CONFIG;
                    17: data=8'h81; 18: data=8'h7F; // contrast
                    19: data=8'hD9; 20: data=8'hF1; // precharge, charge pump use
                    21: data=8'hDB; 22: data=8'h20; // VCOMH
                    23: data=8'hA4; 24: data=8'hA6; // RAM display, normal
                    25: data=8'h2E; // scroll off
                    default: data=8'h00;
                endcase
            end
            1: begin
                length = 11'd7;
                case (index)
                    0: data=8'h00;
                    1: data=8'h21; 2: data=8'h00; 3: data=8'h7F;
                    4: data=8'h22; 5: data=8'h00; 6: data=LAST_PAGE;
                    default: data=8'h00;
                endcase
            end
            2: begin
                length = FRAME_LENGTH;
                if (index == 0) data=8'h40; // Co=0, D/C#=1: GDDRAM pixels
                else data=glyph(index-11'd1);
            end
            3: begin
                length=11'd2;
                if (index == 0) data=8'h00;
                else data=8'hAF;
            end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= WAIT_POWER; wait_count <= 0;
            packet <= 0; start <= 0;
            pass <= 0; fail <= 0; nack_seen <= 0; timeout_seen <= 0;
        end else begin
            start <= 0;
            case (state)
                WAIT_POWER: if (wait_count >= WAIT_CYCLES-1) state <= LAUNCH;
                            else wait_count <= wait_count+1;
                LAUNCH: if (!busy) begin start <= 1; state <= WAIT_PACKET; end
                WAIT_PACKET: if (done) begin
                    if (nack || timeout_error) begin
                        fail <= 1; nack_seen <= nack; timeout_seen <= timeout_error;
                        state <= ERROR;
                    end else if (packet == 3) begin pass <= 1; state <= FINISH; end
                    else begin packet <= packet+1; state <= LAUNCH; end
                end
                FINISH: state <= FINISH;
                ERROR: state <= ERROR; // press btnC to retry after wiring fix
                default: state <= WAIT_POWER;
            endcase
        end
    end
    assign led[15] = pass; // all bytes ACKed; does not prove panel illumination
    assign led[14] = fail;
    assign led[13] = nack_seen;
    assign led[12] = (state != FINISH) && (state != ERROR);
    assign led[11] = timeout_seen;
    assign led[10:0] = 11'b0;
endmodule
