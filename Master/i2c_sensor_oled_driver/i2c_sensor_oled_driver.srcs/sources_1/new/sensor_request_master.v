`timescale 1ns / 1ps
// The published registers describe ONE request, never a mixture of requests.
// Both transports share register selectors 01/02/03 and a 16-bit response.
module sensor_request_master #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SPI_HZ = 100_000,
    parameter integer BOARD_I2C_HZ = 100_000,
    parameter integer TIMEOUT_MS = 250,
    parameter [6:0] SLAVE_ADDR = 7'h42,
    parameter integer SPI_PROTOCOL_READY = 0,
    parameter [7:0] CMD_TEMP = 8'h01,
    parameter [7:0] CMD_HUMI = 8'h02,
    parameter [7:0] CMD_DIST = 8'h03
)(
    input wire clk, reset, request,
    input wire [1:0] mode, // 01 = SPI, 10 = board I2C
    input wire [2:0] request_mask, // {distance,humidity,temperature}
    input wire spi_miso,
    inout wire board_sda, board_scl,
    output wire spi_sclk, spi_mosi, spi_cs_n,
    output reg [7:0] temperature, humidity,
    output reg [8:0] distance,
    output reg [2:0] valid_mask,
    output reg busy, update,
    output reg [2:0] error_code // 1=mode, 2=empty, 3=SPI disabled, 4=NACK, 5=timeout, 6=bad padding
);
    localparam IDLE=0, SELECT=1, LAUNCH=2, RECEIVE=3, COMMIT=4;
    reg [2:0] state, mask;
    reg [1:0] sensor;
    reg [1:0] active_mode;
    reg [7:0] pending_temp, pending_humi;
    reg [8:0] pending_dist;
    reg spi_start, i2c_start;
    wire spi_busy, spi_done;
    wire i2c_busy, i2c_done, i2c_nack, i2c_timeout;
    wire [15:0] spi_response, i2c_response;
    wire [15:0] response = active_mode == 2 ? i2c_response : spi_response;
    // Slave pads every valid value to 16 bits with zero upper bits.
    wire bad_padding = sensor == 2 ? |response[15:9] : |response[15:8];
    wire [7:0] command = sensor == 0 ? CMD_TEMP :
                              sensor == 1 ? CMD_HUMI : CMD_DIST;
    spi_master_transfer #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ)) transport (
        .clk(clk),
        .reset(reset),
        .start(spi_start),
        .command(command),
        .spi_miso(spi_miso),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .busy(spi_busy),
        .done(spi_done),
        .response(spi_response)
    );
    i2c_sensor_read_master #(.CLK_HZ(CLK_HZ),.I2C_HZ(BOARD_I2C_HZ),
        .TIMEOUT_MS(TIMEOUT_MS),.SLAVE_ADDR(SLAVE_ADDR)) board_i2c (
        .clk(clk),.reset(reset),.start(i2c_start),.command(command),
        .sda(board_sda),.scl(board_scl),.busy(i2c_busy),.done(i2c_done),
        .nack(i2c_nack),.timeout_error(i2c_timeout),.response(i2c_response)
    );
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; mask <= 0; sensor <= 0; active_mode <= 0;
            pending_temp <= 0; pending_humi <= 0; pending_dist <= 0;
            temperature <= 0; humidity <= 0; distance <= 0;
            valid_mask <= 0; busy <= 0; update <= 0;
            error_code <= 0; spi_start <= 0; i2c_start <= 0;
        end else begin
            spi_start <= 0; i2c_start <= 0; update <= 0;
            case (state)
                IDLE: if (request) begin
                    temperature <= 0; humidity <= 0; distance <= 0;
                    valid_mask <= 0; update <= 1; error_code <= 0;
                    pending_temp <= 0; pending_humi <= 0; pending_dist <= 0;
                    mask <= request_mask; sensor <= 0; active_mode <= mode;
                    if (mode != 2'b01 && mode != 2'b10) error_code <= 1;
                    else if (request_mask == 0) error_code <= 2;
                    else if (mode == 2'b01 && !SPI_PROTOCOL_READY) error_code <= 3;
                    else begin busy <= 1; state <= SELECT; end
                end
                SELECT: if (mask[sensor]) state <= LAUNCH;
                        else if (sensor == 2) state <= COMMIT;
                        else sensor <= sensor+1;
                LAUNCH: if (!spi_busy && !i2c_busy) begin
                    if (active_mode == 2) i2c_start <= 1;
                    else spi_start <= 1;
                    state <= RECEIVE;
                end
                RECEIVE: if ((active_mode == 1 && spi_done) || (active_mode == 2 && i2c_done)) begin
                    if (active_mode == 2 && (i2c_nack || i2c_timeout)) begin
                        error_code <= i2c_timeout ? 5 : 4;
                        busy <= 0; update <= 1; state <= IDLE;
                    end else if (bad_padding) begin
                        error_code <= 6;
                        busy <= 0; update <= 1; state <= IDLE;
                    end else begin
                    case (sensor)
                        0: pending_temp <= response[7:0];
                        1: pending_humi <= response[7:0];
                        2: pending_dist <= response[8:0];
                    endcase
                    if (sensor == 2) state <= COMMIT;
                    else begin sensor <= sensor+1; state <= SELECT; end
                    end
                end
                COMMIT: begin
                    temperature <= pending_temp; humidity <= pending_humi;
                    distance <= pending_dist; valid_mask <= mask;
                    busy <= 0; update <= 1; state <= IDLE;
                end
                default: begin state <= IDLE; busy <= 0; end
            endcase
        end
    end
endmodule
