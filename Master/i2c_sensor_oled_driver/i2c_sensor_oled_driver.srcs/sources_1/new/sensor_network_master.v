`timescale 1ns / 1ps
// New top; top_master.v remains available as the original OLED abc demo.
module sensor_network_master #(
    parameter CLK_HZ = 100_000_000,
    parameter SPI_HZ = 100_000,
    parameter I2C_HZ = 100_000,
    parameter BOARD_I2C_HZ = 100_000,
    parameter [6:0] SLAVE_ADDR = 7'h42,
    parameter OLED_HEIGHT = 32,
    parameter [6:0] OLED_ADDR = 7'h3C,
    parameter POWERUP_MS = 100,
    parameter TIMEOUT_MS = 250,
    parameter BUTTON_CYCLES = 2_000_000,
    parameter SPI_PROTOCOL_READY = 1,
    parameter OLED_SELF_TEST = 0,
    parameter [7:0] CMD_TEMP = 8'h01,
    parameter [7:0] CMD_HUMI = 8'h02,
    parameter [7:0] CMD_DIST = 8'h03
)(
    input wire clk, btnC,
    input wire [15:0] sw,
    input wire spi_miso,
    output wire spi_sclk, spi_mosi, spi_cs_n,
    inout wire board_sda, board_scl,
    inout wire oled_sda, oled_scl,
    output wire [15:0] led
);
    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_pipe = 4'b1111;
    always @(posedge clk or posedge sw[15])
        if (sw[15]) reset_pipe <= 4'b1111;
        else reset_pipe <= {reset_pipe[2:0],1'b0};
    wire reset = reset_pipe[3];
    (* ASYNC_REG = "TRUE" *) reg [4:0] sw_meta, sw_sync;
    always @(posedge clk) begin
        if (reset) begin sw_meta <= 0; sw_sync <= 0; end
        else begin sw_meta <= sw[4:0]; sw_sync <= sw_meta; end
    end
    wire request, request_busy, display_update;
    wire [7:0] temperature, humidity;
    wire [8:0] distance;
    wire [2:0] valid_mask, error_code;
    wire oled_ready, oled_error, oled_nack, oled_timeout;
    request_button #(.STABLE_CYCLES(BUTTON_CYCLES)) button (
        .clk(clk),.reset(reset),.button(btnC),.pressed(request)
    );
    sensor_request_master #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ),
        .BOARD_I2C_HZ(BOARD_I2C_HZ),.TIMEOUT_MS(TIMEOUT_MS),.SLAVE_ADDR(SLAVE_ADDR),
        .SPI_PROTOCOL_READY(SPI_PROTOCOL_READY),
        .CMD_TEMP(CMD_TEMP),.CMD_HUMI(CMD_HUMI),.CMD_DIST(CMD_DIST)) acquisition (
        .clk(clk),
        .reset(reset),
        .request(request),
        .mode(sw_sync[1:0]),
        .request_mask(sw_sync[4:2]),
        .spi_miso(spi_miso),
        .board_sda(board_sda),
        .board_scl(board_scl),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .temperature(temperature),.humidity(humidity),.distance(distance),
        .valid_mask(valid_mask),.busy(request_busy),.update(display_update),.error_code(error_code)
    );
    // Board I2C and OLED I2C use physically separate open-drain buses.
    oled_sensor_display #(.CLK_HZ(CLK_HZ),.I2C_HZ(I2C_HZ),
        .OLED_HEIGHT(OLED_HEIGHT),.OLED_ADDR(OLED_ADDR),
        .POWERUP_MS(POWERUP_MS),.TIMEOUT_MS(TIMEOUT_MS)) display (
        .clk(clk),.reset(reset),.update(display_update),
        .valid_mask(OLED_SELF_TEST ? 3'b111 : valid_mask),
        .temperature(OLED_SELF_TEST ? 8'd25 : temperature),
        .humidity(OLED_SELF_TEST ? 8'd60 : humidity),
        .distance(OLED_SELF_TEST ? 9'd123 : distance),
        .oled_sda(oled_sda),.oled_scl(oled_scl),.ready(oled_ready),.error(oled_error),
        .nack_seen(oled_nack),.timeout_seen(oled_timeout)
    );
    assign led = {oled_ready,oled_error,oled_nack,oled_timeout,request_busy,
                  (SPI_PROTOCOL_READY == 0),(error_code == 4),(error_code == 1),
                  (error_code == 2),valid_mask,(error_code == 5),(error_code == 6),2'b0};
endmodule
