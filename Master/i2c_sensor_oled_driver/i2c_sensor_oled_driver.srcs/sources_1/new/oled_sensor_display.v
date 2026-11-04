`timescale 1ns / 1ps
// SSD1306 128x32/64, three 5x7 text rows. The entire GDDRAM is rewritten,
// including blanks, so an omitted field cannot leave old pixels behind.
module oled_sensor_display #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter integer OLED_HEIGHT = 32,
    parameter [6:0] OLED_ADDR = 7'h3C,
    parameter integer POWERUP_MS = 100,
    parameter integer TIMEOUT_MS = 250
)(
    input wire clk, reset, update,
    input wire [2:0] valid_mask,
    input wire [7:0] temperature, humidity,
    input wire [8:0] distance,
    inout wire oled_sda, oled_scl,
    output reg ready, error, nack_seen, timeout_seen
);
    localparam integer WAIT_CYCLES = POWERUP_MS == 0 ? 1 : (CLK_HZ/1000)*POWERUP_MS;
    localparam [7:0] MUX = OLED_HEIGHT-1;
    localparam [7:0] COM_CONFIG = OLED_HEIGHT == 64 ? 8'h12 : 8'h02;
    localparam [7:0] LAST_PAGE = OLED_HEIGHT/8-1;
    localparam WAIT_POWER=0, PREPARE=1, LAUNCH=2, WAIT_PACKET=3, IDLE=4, ERROR=5;
    reg [2:0] state;
    reg [1:0] packet;
    reg [2:0] page;
    reg [31:0] wait_count;
    reg start, pending;
    reg [2:0] frame_valid;
    reg [7:0] frame_temp, frame_humi;
    reg [8:0] frame_dist;
    reg [10:0] length;
    reg [7:0] data;
    wire [10:0] index;
    wire busy, done, nack, timeout_error;
    i2c_write_master #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ),.TIMEOUT_MS(TIMEOUT_MS)) oled_bus (
        .clk(clk),.reset(reset),.start(start),.address(OLED_ADDR),
        .length(length),.byte_index(index),.byte_data(data),
        .busy(busy),.done(done),.nack(nack),.timeout_error(timeout_error),
        .sda(oled_sda),.scl(oled_scl)
    );

    function [7:0] text_char;
        input [2:0] row;
        input [4:0] character;
        input [2:0] validity;
        input [7:0] temp_value, humi_value;
        input [8:0] dist_value;
        reg [95:0] label_text;
        reg [8:0] value;
        reg valid;
        begin
            label_text = 0; value = 0; valid = 0;
            case (row)
                0: begin label_text="Temperature:"; value={1'b0,temp_value}; valid=validity[0]; end
                1: begin label_text="Humidity:   "; value={1'b0,humi_value}; valid=validity[1]; end
                2: begin label_text="Distance:   "; value=dist_value; valid=validity[2]; end
            endcase
            text_char = " ";
            if (row < 3) begin
                if (character < 12) text_char=label_text[(11-character)*8 +: 8];
                else if (valid) begin
                    case (character)
                        13: if (value >= 100) text_char=8'd48+value/100;
                        14: if (value >= 10) text_char=8'd48+(value/10)%10;
                        15: text_char=8'd48+value%10;
                    endcase
                end
            end
        end
    endfunction

    function [7:0] font_column;
        input [7:0] character;
        input [2:0] column;
        reg [39:0] pixels;
        begin
            // Least significant byte is the leftmost column, bit 0 is top.
            case (character)
                "T": pixels=40'h01017F0101;
                "H": pixels=40'h7F0808087F;
                "D": pixels=40'h1C2241417F;
                "a": pixels=40'h7854545420;
                "c": pixels=40'h2044444438;
                "d": pixels=40'h7F44444830;
                "e": pixels=40'h1854545438;
                "i": pixels=40'h00407D4400;
                "m": pixels=40'h780418047C;
                "n": pixels=40'h780404087C;
                "p": pixels=40'h081414147C;
                "r": pixels=40'h080404087C;
                "s": pixels=40'h2054545448;
                "t": pixels=40'h20443F0404;
                "u": pixels=40'h7C2040403C;
                "y": pixels=40'h3C5050500C;
                ":": pixels=40'h0000363600;
                "0": pixels=40'h3E4549513E;
                "1": pixels=40'h00407F4200;
                "2": pixels=40'h4649516142;
                "3": pixels=40'h314B454121;
                "4": pixels=40'h107F121418;
                "5": pixels=40'h3945454527;
                "6": pixels=40'h3049494A3C;
                "7": pixels=40'h0305097101;
                "8": pixels=40'h3649494936;
                "9": pixels=40'h1E29494906;
                default: pixels=0;
            endcase
            font_column = 0;
            if (column < 5) font_column=pixels[column*8 +: 8];
        end
    endfunction

    // Four registered stages replace the long index -> /6 -> ASCII -> font
    // combinational path. The unchanged I2C core advances byte_index in
    // NEXT_BYTE and samples byte_data in LOAD_BYTE one quarter-period later.
    // Therefore Q must be at least 5 clocks (default Q=250; test Q=12).
    localparam integer PIXEL_PIPELINE_CYCLES = 4;
    // synthesis translate_off
    initial begin
        if (CLK_HZ/(4*I2C_HZ) <= PIXEL_PIPELINE_CYCLES)
            $fatal(1,"OLED I2C quarter-period must exceed the 4-clock pixel pipeline");
    end
    // synthesis translate_on
    reg [10:0] pixel;
    reg [2:0] pixel_row, glyph_column, font_column_q;
    reg [4:0] character_index;
    reg [7:0] character_q, frame_pixel_q;
    always @(posedge clk) begin
        if (reset) begin
            pixel <= 0; pixel_row <= 0; glyph_column <= 0;
            character_index <= 0; character_q <= " ";
            font_column_q <= 0; frame_pixel_q <= 0;
        end else begin
            pixel <= {1'b0,page,7'b0}+index-11'd1;
            pixel_row <= pixel[9:7];
            character_index <= pixel[6:0]/6;
            glyph_column <= pixel[6:0]%6;
            character_q <= text_char(pixel_row,character_index,
                                    frame_valid,frame_temp,frame_humi,frame_dist);
            font_column_q <= glyph_column;
            frame_pixel_q <= font_column(character_q,font_column_q);
        end
    end
    always @* begin
        data=0; length=2;
        case (packet)
            0: begin
                length=26;
                case (index)
                    0: data=8'h00; 1: data=8'hAE;
                    2: data=8'hD5; 3: data=8'h80;
                    4: data=8'hA8; 5: data=MUX;
                    6: data=8'hD3; 7: data=8'h00; 8: data=8'h40;
                    9: data=8'h8D; 10: data=8'h14;
                    11: data=8'h20; 12: data=8'h02; // SSD1306 page addressing
                    13: data=8'hA1; 14: data=8'hC8;
                    15: data=8'hDA; 16: data=COM_CONFIG;
                    17: data=8'h81; 18: data=8'h7F;
                    19: data=8'hD9; 20: data=8'hF1;
                    21: data=8'hDB; 22: data=8'h20;
                    23: data=8'hA4; 24: data=8'hA6; 25: data=8'h2E;
                endcase
            end
            1: begin
                // Explicit page/column address before every 128-byte transfer.
                length=4;
                case (index)
                    0: data=0;
                    1: data=8'hB0+page;
                    2: data=8'h00;
                    3: data=8'h10;
                endcase
            end
            2: begin
                length=129; // control byte + one full page
                if (index == 0) data=8'h40;
                else data=frame_pixel_q;
            end
            3: begin length=2; data=index == 0 ? 8'h00 : 8'hAF; end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= WAIT_POWER; packet <= 0; page <= 0; wait_count <= 0;
            start <= 0; pending <= 1;
            frame_valid <= 0; frame_temp <= 0; frame_humi <= 0; frame_dist <= 0;
            ready <= 0; error <= 0; nack_seen <= 0; timeout_seen <= 0;
        end else begin
            start <= 0;
            if (update) pending <= 1;
            case (state)
                WAIT_POWER: if (wait_count >= WAIT_CYCLES-1) state <= PREPARE;
                            else wait_count <= wait_count+1;
                PREPARE: begin
                    page <= 0;
                    frame_valid <= valid_mask; frame_temp <= temperature;
                    frame_humi <= humidity; frame_dist <= distance;
                    pending <= 0; state <= LAUNCH;
                end
                LAUNCH: if (!busy) begin start <= 1; state <= WAIT_PACKET; end
                WAIT_PACKET: if (done) begin
                    if (nack || timeout_error) begin
                        error <= 1; ready <= 0;
                        nack_seen <= nack; timeout_seen <= timeout_error;
                        state <= ERROR;
                    end else if (packet == 3) begin ready <= 1; state <= IDLE; end
                    else if (packet == 2) begin
                        if (page == LAST_PAGE) packet <= 3;
                        else begin page <= page+1; packet <= 1; end
                        state <= LAUNCH;
                    end
                    else begin packet <= packet+1; state <= LAUNCH; end
                end
                IDLE: if (pending || update) begin
                    // Snapshot at the frame boundary; later updates remain pending.
                    packet <= 1; state <= PREPARE;
                end
                ERROR: state <= ERROR;
                default: state <= WAIT_POWER;
            endcase
        end
    end
endmodule
