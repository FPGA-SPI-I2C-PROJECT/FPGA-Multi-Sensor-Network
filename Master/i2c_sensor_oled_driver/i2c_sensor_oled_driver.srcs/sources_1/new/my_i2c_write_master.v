module my_i2c_master #(
    parameter CLK_HZ = 100_000_000,
    parameter I2C_HZ = 100_000,
    parameter BYTE_MAX = 1_000_000,  // I2C로 보낼 최대 데이터 갯수. 지금은 임의의 값이고 이후 TOP에서 parameter 값을 변경할 수 있다.
    
    parameter START_HOLDTIME_MIN = 600,    // ns + SDA가 먼저 떨어지고 600 ns 뒤에 SCL이 떨어져야한다.
    parameter START_SETUPTIME_MIN = 600,   // ns (only Only relevant for a repeated Start condition)
    parameter STOP_SETUPTIME_MIN = 600,    // ns
    parameter DATA_SETUPTIME_MIN = 100,    // ns
    parameter DATA_HOLDTIME_MIN = 300,     // ns
    parameter RISING_TIME_MAX = 300,       // ns data, clk 둘다
    parameter FALLING_TIME_MAX = 300,      // ns data, clk 둘다
    parameter IDLE_TIME_MIN = 1300,        // ns 새로운 전송을 시작할 수 있을 때까지 IDLE 상태를 유지해야하는 시간
    parameter TIMEOUT_MS = 250
)(
    input clk,
    input reset,
    input start,
    input [7:0] slave_address_RW,
    input [$clog2(BYTE_MAX)-1:0] length,
    input [7:0] byte_data,
    output reg [$clog2(BYTE_MAX)-1:0] byte_index,
    output reg busy, done,
    output reg nack, timeout_error,
    output timing_violation,
    inout scl, sda
    );

    // about time
    localparam CLK_PERIOD = 1_000_000_000 / CLK_HZ; // ns
    localparam I2C_PERIOD = 1_000_000_000 / I2C_HZ; // ns
    localparam STANDARD_I2C_FREQ_MAX = 100_000;
    localparam FASTMODE_I2C_FREQ_MAX = 400_000;
    localparam FASTMODE_PLUS_I2C_FREQ_MAX = 1_000_000;
    localparam CLK_CYCLE_TIME_MIN = (I2C_HZ <= STANDARD_I2C_FREQ_MAX) ? 10_000 : (I2C_HZ <= FASTMODE_I2C_FREQ_MAX) ? 2500 : 1000;   // ns
    
    localparam CLK_TICK_FOR_START_HOLDTIME_MIN = START_HOLDTIME_MIN / CLK_PERIOD;    // 60
    localparam CLK_TICK_FOR_START_SETUPTIME_MIN = START_SETUPTIME_MIN / CLK_PERIOD;  // 60
    localparam CLK_TICK_FOR_STOP_SETUPTIME_MIN = STOP_SETUPTIME_MIN / CLK_PERIOD;    // 60

    localparam CLK_TICK_FOR_DATA_SETUPTIME_MIN = DATA_SETUPTIME_MIN / CLK_PERIOD;    // 10
    localparam CLK_TICK_FOR_DATA_HOLDTIME_MIN = DATA_HOLDTIME_MIN / CLK_PERIOD;      // 30
    localparam DATA_CHANGE_POINT = (CLK_HZ / I2C_HZ - (CLK_TICK_FOR_DATA_SETUPTIME_MIN + CLK_TICK_FOR_DATA_HOLDTIME_MIN)) / 2;

    localparam CLK_TICK_FOR_RISING_TIME_MAX = RISING_TIME_MAX / CLK_PERIOD;          // 30
    localparam CLK_TICK_FOR_FALLING_TIME_MAX = FALLING_TIME_MAX / CLK_PERIOD;        // 30
    localparam CLK_TICK_FOR_IDLE_TIME_MIN = IDLE_TIME_MIN / CLK_PERIOD;              // 130
    localparam MARGIN_PERCENT = 10;               // margin time ratio on setup/hold time for preventing violation
    localparam CLK_TICK_FOR_TIMEOUT = TIMEOUT_MS * CLK_HZ / 1000; // 250 ms / 10 ns = CLK_HZ * 250 / 1000

    // state 관련 parameter
    localparam [2:0]    IDLE = 0, START_CONDITION = 1, DATA_SETUP = 2,
                        DATA_HOLD = 3, ACK_NACK = 4, STOP_CONDITION = 5;

    reg [2:0] state, prev_state;  // IDLE -> START_CONDITION ->
    reg [$clog2(BYTE_MAX)-1:0] tx_cnt;
    reg [$clog2(I2C_HZ/2)-1:0] HALF_SCL_FREQ;
    reg [$clog2(CLK_HZ / I2C_HZ)-1:0] time_cnt, scl_cnt;
    reg [$clog2(CLK_TICK_FOR_TIMEOUT)-1:0] watchdog;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg is_address;
    reg setup_satisfied, hold_satisfied;

    // data setup/hold time의 합이 I2C 주기보다 크면 무조건 timing violoatin 발생
    assign timing_violation = (I2C_PERIOD < DATA_SETUPTIME_MIN + DATA_HOLDTIME_MIN) ? 1 : 0;

    (* ASYNC_REG = "TRUE" *) reg [1:0] scl_sync, sda_sync;
    reg scl_low, sda_low;
    assign scl = (scl_low) ? 1'b0 : 1'bz;
    assign sda = (sda_low) ? 1'b0 : 1'bz;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
        end
        else begin
            scl_sync <= {scl_sync[0], scl};
            sda_sync <= {sda_sync[0], sda};
            prev_state <= state;
        end
    end

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            state <= IDLE;
            time_cnt <= 0; scl_cnt <= 0;watchdog <= 0;
            sda_low <= 0; scl_low <= 0;
            busy <= 0; done <= 0; nack <=0; timeout_error <= 0;
            byte_index <= 0; tx_cnt <= 0;
            shift <= 0; bit_index <= 7; is_address <= 1'b1;
            
        end

        else begin
            if(!busy) begin
                time_cnt <= 0; scl_cnt <= 0; watchdog <= 0;
                if(start) begin
                    busy <= 1; done <= 1'b0; nack <= 1'b0; timeout_error <= 1'b0;
                    byte_index <= 0; tx_cnt <= length;
                    shift <= slave_address_RW;
                    bit_index <= 7; is_address <= 1'b1;
                    state <= START_CONDITION;
                end
            end

            else if(watchdog >= CLK_TICK_FOR_TIMEOUT - 1) begin
                timeout_error <= 1'b1;
                busy <= 1'b0; done <= 1'b1;
                sda_low <= 0; scl_low <= 0;
                state <= IDLE;
            end

            else begin
                watchdog <= watchdog + 1;
                case (state)
                    START_CONDITION: begin
                        if(prev_state == IDLE) begin
                            time_cnt <= 0;
                            scl_cnt <= 0;
                            sda_low <= 1'b1;
                        end

                        else if(scl_cnt >= (CLK_TICK_FOR_START_HOLDTIME_MIN * (100 + MARGIN_PERCENT))/100 -1) begin
                            scl_cnt <= 0;
                            scl_low <= 1'b1;
                            if(I2C_PERIOD + 10 < DATA_SETUPTIME_MIN)
                                sda_low <= !shift[bit_index];
                            state <= DATA_SETUP;
                        end

                        else scl_cnt <= scl_cnt + 1;
                    end
                    DATA_SETUP: begin
                        if(I2C_PERIOD < DATA_SETUPTIME_MIN)
                            sda_low <= !shift[bit_index];
                        
                        if(time_cnt >= I2C_HZ/2 -1) begin
                            time_cnt <= 0;
                            scl_low <= 1'b0;
                            state <= DATA_HOLD;
                            bit_index <= bit_index - 1;

                        end
                        else begin
                            time_cnt <= time_cnt + 1;
                            if(time_cnt >= I2C_HZ / 2 - CLK_TICK_FOR_DATA_SETUPTIME_MIN * (100 + MARGIN_PERCENT)/100 -1) begin
                                sda_low <= !shift[bit_index];
                            end
                        end

                        if(scl_cnt >= I2C_HZ -1) begin
                            scl_cnt <= 0;
                            scl_low <= 1'b1;
                        end
                        else begin
                            scl_cnt <= scl_cnt + 1;
                            if(scl_cnt >= I2C_HZ / 2 - 1) scl_low <= 1'b0;
                        end
                    end

                    DATA_HOLD: begin
                        time_cnt <= time_cnt + 1;
                        if(time_cnt >= I2C_HZ/2 -1 ) begin
                            time_cnt <=0;
                            
                        end
                    end
                endcase


            end
        end
    end 
    

endmodule