`timescale 1ns/1ps
// Diagnostic ONLY: continuous 100 kHz open-drain clock, not an I2C transfer.
// Disconnect the OLED but keep the external 4.7k pull-up to 3.3V.
// Select this module as Vivado Top; use only basys3_JA7_JA8.xdc.
module scl_pin_test (
    input wire clk,
    input wire btnC,
    inout wire oled_sda,
    inout wire oled_scl,
    output wire [15:0] led
);
    reg [8:0] count = 0;
    reg scl_low = 0;
    reg [25:0] heartbeat_count = 0;
    reg heartbeat = 0;

    always @(posedge clk) begin
        if (btnC) begin
            count <= 0;
            scl_low <= 0;
            heartbeat_count <= 0;
            heartbeat <= 0;
        end else begin
            // 100 MHz / (2 * 500) = 100 kHz.
            if (count == 9'd499) begin
                count <= 0;
                scl_low <= ~scl_low;
            end else count <= count + 1'b1;
            if (heartbeat_count == 26'd49_999_999) begin
                heartbeat_count <= 0;
                heartbeat <= ~heartbeat;
            end else heartbeat_count <= heartbeat_count + 1'b1;
        end
    end
    assign oled_scl = scl_low ? 1'b0 : 1'bz;
    assign oled_sda = 1'bz;
    assign led = {heartbeat, 14'b0, btnC};
endmodule

