module my_i2c_write_master #(
    parameter CLK_HZ = 100_000_000,
    parameter I2C_HZ = 100_000
)(
    input clk,
    input reset,
    input start,
    input [6:0] slave_address,
    input [10:0] length,
    input [7:0] byte_data,
    output reg [10:0] byte_index,
    output busy, done,
    output nack, timeout_error,
    input scl, sda
    );

    localparam STANDARD_I2C_FREQ_MAX = 100_000;
    localparam FASTMODE_I2C_FREQ_MAX = 400_000;
    localparam FASTMODE_PLUS_I2C_FREQ_MAX = 1_000_000;
    localparam CLK_CYCLE_TIME_MIN = (I2C_HZ <= 100_000) ? 10_000 : (I2C_HZ <= 400_000) ? 2500 : 1000;   // ns
    localparam START_HOLDTIME_MIN = 600;    // ns + SDA가 먼저 떨어지고 600 ns 뒤에 SCL이 떨어져야한다.
    localparam DATA_SETUPTIME_MIN = 100;    // ns
    localparam DATA_HOLDTIME_MIN = 300;     // ns
    localparam START_SETUPTIME_MIN = 600;   // ns (only Only relevant for a repeated Start condition)
    localparam STOP_SETUPTIME_MIN = 600;    // ns
    localparam RISING_TIME_MAX = 300;       // ns data, clk 둘다
    localparam FALLING_TIME_MAX = 300;      // ns data, clk 둘다
    localparam IDLE_TIME_MIN = 1300;        // ns 새로운 전송을 시작할 수 있을 때까지 IDLE 상태를 유지해야하는 시간.
    localparam TIMEOUT_MS = 250;
    reg state;
    reg [$clog2(CLK_HZ / I2C_HZ)-1:0] time_cnt, watchdog;

    (* ASYNC_REG = "TRUE" *) reg [1:0] scl_sync, sda_sync;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            
        end
    end 
    

endmodule