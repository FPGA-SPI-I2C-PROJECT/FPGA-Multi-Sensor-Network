`timescale 1ns / 1ps
// Single-master, write-only I2C packet transmitter. No derived logic clocks.
// byte_data must be combinational data selected by byte_index.
// Packet: START, {address,0}, byte_data[0..length-1], STOP.
module i2c_write_master #(
    parameter integer CLK_HZ = 100_000_000, // 100 MHz
    parameter integer I2C_HZ = 100_000, // 100 kHz // T = 1 / 100k = 10 us
    parameter integer TIMEOUT_MS = 250  // 250 ms
)(
    input clk,
    input reset,
    input start,
    input [6:0] address,
    input [10:0] length,
    input [7:0] byte_data,
    output reg [10:0] byte_index,
    output reg busy, output reg done,
    output reg nack, output reg timeout_error,
    inout wire sda, inout wire scl
);
    localparam integer Q = CLK_HZ / (4 * I2C_HZ);   // 100 kHz의 1/4주기
    localparam integer LIMIT = (CLK_HZ / 1000) * TIMEOUT_MS;
    localparam [4:0] IDLE=0, BUS_FREE=1, START_HOLD=2, START_LOW=3,
        BIT_SET=4, BIT_RISE=5, BIT_HIGH=6, BIT_FALL=7,
        ACK_SET=8, ACK_RISE=9, ACK_HIGH=10, ACK_FALL=11,
        NEXT_BYTE=12, LOAD_BYTE=13, STOP_SET=14, STOP_RISE=15,
        STOP_HIGH=16, STOP_RELEASE=17, STOP_FREE=18;
    reg [4:0] state;
    reg [31:0] divider, watchdog;
    reg sda_low, scl_low;
    reg [7:0] shift;
    reg [2:0] bit_index;
    reg sending_address;
    reg [10:0] count;                                       // 
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync, scl_sync;  // 동기화 레지스터 [1]: prev_sync
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    always @(posedge clk) begin
        if (reset) begin
            // sda, scl의 default 값은 High
            sda_sync <= 2'b11;
            scl_sync <= 2'b11;
        end else begin
            // 
            sda_sync <= {sda_sync[0], sda};
            scl_sync <= {scl_sync[0], scl};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            divider <= 0; watchdog <= 0;
            sda_low <= 0; scl_low <= 0;
            busy <= 0; done <= 0; nack <= 0; timeout_error <= 0;
            byte_index <= 0; count <= 0;
            shift <= 0; bit_index <= 7; sending_address <= 1;
        end else begin
            done <= 0;
            if (!busy) begin
                divider <= 0; watchdog <= 0;
                // start 신호가 오면 I2C 통신을 시작한다.
                if (start) begin
                    busy <= 1; nack <= 0; timeout_error <= 0;   // busy <= 1: i2c 통신을 하는 중
                    byte_index <= 0; count <= length;
                    shift <= {address, 1'b0};
                    bit_index <= 7; sending_address <= 1;   //
                    state <= BUS_FREE;  // state를 BUS_FREE로 전환
                end
            end
            // watchdog은 timeout error를 판단하는 역할
            else if (watchdog >= LIMIT-1) begin
                // A stuck clock cannot carry a valid STOP: release both pins.
                timeout_error <= 1;
                // sda_low, scl_low를 0으로 하면 external pull-up register에 의해 SCL과 SDA는 High가 된다.
                sda_low <= 0; scl_low <= 0;
                busy <= 0; done <= 1; state <= IDLE;    // i2c 통신이 가능한 초기 상태로 돌린다.
            end else begin
                watchdog <= watchdog + 1;
                // divider는 100 khZ의 1/4주기를 센다.
                if (divider == Q-1) begin
                    divider <= 0;
                    case (state)
                        BUS_FREE: if (sda_sync[1] && scl_sync[1]) begin                 // SDA 버스가 FREE한 상태(비어있는 상태)
                            sda_low <= 1; state <= START_HOLD;                          // start 신호가 오면 1/4 SCL_PERIOD(=2.5 us) 뒤에 SDA를 Low로.
                        end
                        START_HOLD: begin scl_low <= 1; state <= START_LOW; end         // SDA가 Low가 되고 1/4 SCL_PERIOD 뒤에 SCL도 Low로 만들어 I2C 통신 start.
                        START_LOW: state <= BIT_SET;                                    // 2/4 SCL_PERIOD: state를 BIT_SET으로 전환
                        BIT_SET: begin
                            // 3/4 SCLPERIOD: slave address를 보내기 시작. shift reg의 MSB부터 보낸다. sda_low는 HIGH일 때 SDA를 LOW로 만드므로, shift[bit_index]의 값과 반전된 값을 넣어야한다. ex) shift[7] = 1 => sda_low = 0
                            // 7/4 SCL_PERIOD: bit_index = 6. shift[6]에 따라서 SDA 값을 정하고 state <= RISE로 이동.
                            sda_low <= !shift[bit_index]; state <= BIT_RISE;
                        end
                        BIT_RISE: begin
                            scl_low <= 0; state <= BIT_HIGH; end                        // 4/4 SCL_PERIOD: SCL의값을 반전시켜야함. (LOW -> HIGH) 아직까지 SDA에는 shift[7] 값을 나타낸다.
                        BIT_HIGH: if (scl_sync[1]) state <= BIT_FALL;                   // 5/4 SCL_PERIOD: scl_sync[1] =1 --> 이전에 scl = 1 --> state를 BIT_FALL로
                        BIT_FALL: begin                                                 // 6/4 SCL_PERIOD: 여기서 SDA에 다른 데이터를 보낼 준비를 해야함.
                            scl_low <= 1;                                               // scl_low <= 1 --> SCL을 HIGH -> LOW.
                            if (bit_index == 0) state <= ACK_SET;                       // bit_index가 0이면, 이미 모든 데이터를 SDA에 반영한 상태일 것이기 때문에 state를 ACK로 보낸다.
                            else begin bit_index <= bit_index-1; state <= BIT_SET; end  // bit_index를 낮춰서 다음 비트를 보낼 준비를 한다. 비트를 보내야하니, state를 BIT_SET 상태로 이동.
                        end
                        ACK_SET: begin sda_low <= 0; state <= ACK_RISE; end             // 35/4 SCL_PERIOD: SDA를 High-Z 상태로 설정해서 Slave에서 오는 ACK 신호를 읽는다. 그리고, ACK_RISE 상태로 이동
                        ACK_RISE: begin scl_low <= 0; state <= ACK_HIGH; end            // 36/4 SCL_PERIOD: scl도 HIGH로 만들어서 통신 ACK 신호를 읽게 한다.
                        ACK_HIGH: if (scl_sync[1]) begin                                // Slave가 ACK을 보낸 경우 10 ns 전의 SDA는 LOW이다. 그런데, 10 ns 전의 SDA가 HIGH라면, Slave가 NACK을 보낸 것이기 때문에, nack <=1로 해준다. ACK_FALL 상태로 이동한다.
                            if (sda_sync[1]) nack <= 1;
                            state <= ACK_FALL;
                        end
                        ACK_FALL: begin scl_low <= 1; state <= NEXT_BYTE; end           // 0/4 SCL_PERIOD: scl_low를 HIGH -> LOW로 떨어뜨리고, state를 NEXT_BYTE로.
                        NEXT_BYTE: begin                                                // 1/4 SCLK_PERIOD: 새로운 데이터 전송을 준비하는 상태.
                            if (nack) state <= STOP_SET;                                // nack =1 이라면 Slave가 데이터를 다 받았다는 것이므로, STOP_SET 상태로 이동.
                            else if (sending_address) begin                             // Slave ACK를 보낸 상태. sending_address가 1이라면 방금 보낸 1 byte는 slave의 address이다.
                                sending_address <= 0;                                   // sending_address를 0으로 하고, 이제 1byte data를 보내야 한다.
                                if (count == 0) state <= STOP_SET;                      // count == 0: 보낼 byte가 없다면 STOP_SET state로,
                                else state <= LOAD_BYTE;                                // count가 0이 아니라면 아직 보낼 데이터가 남아있다. LOAD_BYTE 단계로 이동.
                            end else if (byte_index == count-1) state <= STOP_SET;      // sending_address가 1이 아니야. 방금 보낸 1byte는 진짜 data였어. 그러면 byte_index가 count -1과 같은지 확인해. 같다면, 보내야할 데이터를 다 보낸 것이기 때문에, STOP_SET state로 이동해.
                            else begin byte_index <= byte_index+1; state <= LOAD_BYTE; end  // byte_index가 count와 같지 않다면, 아직 data를 덜 보낸 것이기 때문에, byte_index를 +1 해주고, LOAD_BYTE로 이동해.
                        end
                        LOAD_BYTE: begin
                            shift <= byte_data; bit_index <= 7; state <= BIT_SET;       // 2/4 SCLK_PERIOD: shift reg에 진짜 데이터인 byte_data를 실을거야. 다시 MSB부터 보내야 하니, bit_index를 0 -> 7로 해주고, state를 BIT_SET 상태로 바꿀게. 그러면 3/4 SCL_PERIOD가 되는 시점에 BIT_SET 상태에서 시작할 수 있어.
                        end
                        STOP_SET: begin sda_low <= 1; state <= STOP_RISE; end           // 2/4 SCLK_PERIOD: NEXT_BYTE 상태에서 1. slave에서 NACK 신호를 받았거나 2. count == 0이라 더이상 보낼 데이터가 없거나 3. byte_index가 count -1과 같아서 더이상 보낼 데이터가 없으면, STOP_SET으로 오게 된다. SDA를 LOW로 만든다. 
                        STOP_RISE: begin scl_low <= 0; state <= STOP_HIGH; end          // 3/4 SCL_PERIOD: SCL을 먼저 LOW -> HIGH로 먼저 HIGH로 만들고, STOP_HIGH 상태로 이동한다.
                        STOP_HIGH: if (scl_sync[1]) state <= STOP_RELEASE;              // 4/4 SCL_PERIOD: 10 ns 전 SCL이 HIGH로 안정된 상태이면 STOP_RELEASE 상태로 이동.
                        STOP_RELEASE: begin sda_low <= 0; state <= STOP_FREE; end       // SDA를 HIGH로 만들어 STOP condition으로 만들어준다. slave address를 포함한 데이터를 보낼 때는 SCL의 타이밍에 SDA를 맞춰야 하지만, START/STOP condition에서는 SDA에 맞춰서 SCL이 결정되어야 한다. STOP_FREE 상태로 이동.
                        STOP_FREE: begin busy <= 0; done <= 1; state <= IDLE; end       // STOP_FREE 상태에서는 i2c 통신이 끝났기 때문에 busy =0, done = 1로 설정해주고, state를 IDLE로 바꿔준다.
                        default: state <= STOP_SET;
                    endcase
                end else divider <= divider+1;
            end
        end
    end
endmodule
