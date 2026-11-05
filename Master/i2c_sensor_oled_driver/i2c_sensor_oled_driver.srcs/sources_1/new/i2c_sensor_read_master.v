`timescale 1ns / 1ps
// Alternative implementation. Compile instead of the original .v module.
// Single-master, register-select write + repeated START + two-byte read.
module i2c_sensor_read_master #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer I2C_HZ = 100_000,
    parameter integer TIMEOUT_MS = 250,
    parameter [6:0] SLAVE_ADDR = 7'h42
)(
    input wire clk, reset, start,
    input wire [7:0] command,
    inout wire sda, scl,
    output reg busy, done, nack, timeout_error,
    output reg [15:0] response
);
    function automatic integer max_int(input integer a, input integer b);
        max_int = a > b ? a : b;
    endfunction
    function automatic integer ns_cycles(input integer ns);
        ns_cycles = (64'd1 * CLK_HZ * ns + 999_999_999) / 1_000_000_000;
    endfunction

    // Standard-mode up to 100 kHz; Fast-mode up to 400 kHz.
    // Count HIGH time only after synchronized SCL is actually HIGH.
    // localparam HALF = (CLK_HZ + 2*I2C_HZ - 1) / (2*I2C_HZ);
    // localparam LOW_CYCLES = max_int(HALF, ns_cycles(I2C_HZ <= 100_000 ? 4700 : 1300));
    // localparam HIGH_CYCLES = max_int(HALF, ns_cycles(I2C_HZ <= 100_000 ? 4000 : 600));
    // localparam HOLD_CYCLES = max_int(1, ns_cycles(100));
    // localparam SETUP_CYCLES = LOW_CYCLES - HOLD_CYCLES;
    // localparam START_CYCLES = max_int(1, ns_cycles(I2C_HZ <= 100_000 ? 4000 : 600));
    // localparam RESTART_CYCLES = max_int(1, ns_cycles(I2C_HZ <= 100_000 ? 4700 : 600));
    // localparam STOP_CYCLES = START_CYCLES;
    // localparam FREE_CYCLES = max_int(1, ns_cycles(I2C_HZ <= 100_000 ? 4700 : 1300));
    
    // <= 100 kHz : Standard-mode
    // <= 400 kHz : Fast-mode
    // <=   1 MHz : Fast-mode Plus
    localparam integer HALF =
        (CLK_HZ + 2*I2C_HZ - 1) / (2*I2C_HZ);

    // 각 모드의 최소 시간. 단위: ns
    localparam integer MIN_LOW_NS =
        (I2C_HZ <= 100_000) ? 4700 :
        (I2C_HZ <= 400_000) ? 1300 : 500;

    localparam integer MIN_HIGH_NS =
        (I2C_HZ <= 100_000) ? 4000 :
        (I2C_HZ <= 400_000) ?  600 : 260;

    localparam integer MIN_START_NS =
        (I2C_HZ <= 100_000) ? 4000 :
        (I2C_HZ <= 400_000) ?  600 : 260;

    localparam integer MIN_RESTART_NS =
        (I2C_HZ <= 100_000) ? 4700 :
        (I2C_HZ <= 400_000) ?  600 : 260;

    localparam integer MIN_STOP_NS =
        (I2C_HZ <= 100_000) ? 4000 :
        (I2C_HZ <= 400_000) ?  600 : 260;

    localparam integer MIN_FREE_NS =
        (I2C_HZ <= 100_000) ? 4700 :
        (I2C_HZ <= 400_000) ? 1300 : 500;

    // 반주기와 해당 모드의 최소 시간 중 큰 값 사용
    localparam integer LOW_CYCLES =
        max_int(HALF, ns_cycles(MIN_LOW_NS));

    localparam integer HIGH_CYCLES =
        max_int(HALF, ns_cycles(MIN_HIGH_NS));

    // SCL을 Low로 구동한 뒤 SDA를 변경하기까지의 기존 지연
    localparam integer HOLD_CYCLES =
        max_int(1, ns_cycles(100));

    // SDA 설정 후 SCL을 해제하기까지의 나머지 Low 시간
    localparam integer SETUP_CYCLES =
        LOW_CYCLES - HOLD_CYCLES;

    localparam integer START_CYCLES =
        max_int(1, ns_cycles(MIN_START_NS));

    localparam integer RESTART_CYCLES =
        max_int(1, ns_cycles(MIN_RESTART_NS));

    localparam integer STOP_CYCLES =
        max_int(1, ns_cycles(MIN_STOP_NS));

    localparam integer FREE_CYCLES =
        max_int(1, ns_cycles(MIN_FREE_NS));
    localparam MAX_WAIT = max_int(max_int(LOW_CYCLES, HIGH_CYCLES),
                                            max_int(FREE_CYCLES, RESTART_CYCLES));
    // wait_cycles stores the count itself, including a power-of-two maximum.
    localparam TIMER_W = MAX_WAIT > 1 ? $clog2(MAX_WAIT + 1) : 1;
    localparam LIMIT = (64'd1 * CLK_HZ * TIMEOUT_MS + 999) / 1000;
    localparam WD_W = LIMIT > 1 ? $clog2(LIMIT) : 1;

    localparam [3:0] IDLE=0, BUS_FREE=1, START=2,
        TX_BYTE=3, RX_ACK=4, RESTART=5,
        RX_BYTE=6, TX_ACK=7, STOP=8, RECOVER=9;
    reg [3:0] state;
    reg [2:0] phase;
    reg [TIMER_W-1:0] divider;
    reg [WD_W-1:0] watchdog;
    reg [TIMER_W-1:0] wait_cycles;
    reg sda_low, scl_low;
    reg [7:0] tx_shift, register_select;
    reg [2:0] tx_bit;
    reg [3:0] rx_bit, recovery_count;
    reg [1:0] tx_stage;
    reg [15:0] rx_shift;
    reg recovering, recovery_attempted;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync, scl_sync;
    wire elapsed = divider == wait_cycles - 1'b1;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    // Every timed phase starts at divider=0. The timer does not free-run.
    always @* begin
        wait_cycles = HOLD_CYCLES;
        case (state)
            BUS_FREE: wait_cycles = FREE_CYCLES;
            START: wait_cycles = START_CYCLES;
            TX_BYTE, RX_ACK, RX_BYTE, TX_ACK, RECOVER: begin
                if (phase == 1) wait_cycles = SETUP_CYCLES;
                else if (phase == 3) wait_cycles = HIGH_CYCLES;
            end
            RESTART: begin
                if (phase == 1) wait_cycles = SETUP_CYCLES;
                else if (phase == 3) wait_cycles = RESTART_CYCLES;
            end
            STOP: begin
                if (phase == 1) wait_cycles = SETUP_CYCLES;
                else if (phase == 3) wait_cycles = STOP_CYCLES;
                else if (phase == 5) wait_cycles = FREE_CYCLES;
            end
            default: ;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin sda_sync <= 2'b11; scl_sync <= 2'b11; end
        else begin
            sda_sync <= {sda_sync[0], sda};
            scl_sync <= {scl_sync[0], scl};
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; phase <= 0; divider <= 0; watchdog <= 0;
            sda_low <= 0; scl_low <= 0;
            busy <= 0; done <= 0; nack <= 0; timeout_error <= 0; response <= 0;
            tx_shift <= 0; register_select <= 0; tx_bit <= 7; tx_stage <= 0;
            rx_shift <= 0; rx_bit <= 15; recovery_count <= 0;
            recovering <= 0; recovery_attempted <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                divider <= 0; watchdog <= 0;
                sda_low <= 0; scl_low <= 0;
                if (start) begin
                    busy <= 1; nack <= 0; timeout_error <= 0; response <= 0;
                    register_select <= command;
                    tx_shift <= {SLAVE_ADDR, 1'b0}; tx_stage <= 0; tx_bit <= 7;
                    rx_shift <= 0; rx_bit <= 15;
                    recovery_count <= 0; recovering <= 0; recovery_attempted <= 0;
                    state <= BUS_FREE; phase <= 0;
                end
            end else if (watchdog == LIMIT-1) begin
                // Even a stuck bus must not leave either output asserted.
                sda_low <= 0; scl_low <= 0;
                busy <= 0; done <= 1; timeout_error <= 1; response <= 0;
                state <= IDLE; phase <= 0; divider <= 0;
            end else begin
                watchdog <= watchdog + 1'b1;
                if (!elapsed) divider <= divider + 1'b1;
                case (state)
                    BUS_FREE: begin
                        if (!scl_sync[1] || !sda_sync[1]) begin
                            divider <= 0;
                            if (scl_sync[1] && !sda_sync[1] && !recovery_attempted) begin
                                recovering <= 1; recovery_attempted <= 1;
                                recovery_count <= 0; scl_low <= 1;
                                state <= RECOVER; phase <= 0;
                            end
                        end else if (elapsed) begin
                            sda_low <= 1; state <= START; phase <= 0; divider <= 0;
                        end
                    end
                    START: if (elapsed) begin
                        scl_low <= 1; state <= TX_BYTE; phase <= 0; divider <= 0;
                    end

                    // One shared SCL engine for data, ACK and recovery pulses.
                    // 0: hold after falling edge, 1: data setup / remaining LOW,
                    // 2: release SCL and wait for HIGH, 3: full HIGH then fall.
                    TX_BYTE, RX_ACK, RX_BYTE, TX_ACK, RECOVER: begin
                        case (phase)
                            0: if (elapsed) begin
                                case (state)
                                    TX_BYTE: sda_low <= !tx_shift[tx_bit];
                                    TX_ACK: sda_low <= rx_bit == 8;
                                    default: sda_low <= 0;
                                endcase
                                phase <= 1; divider <= 0;
                            end
                            1: if (elapsed) begin
                                scl_low <= 0; phase <= 2; divider <= 0;
                            end
                            2: begin
                                divider <= 0;
                                if (scl_sync[1]) phase <= 3;
                            end
                            3: if (elapsed) begin
                                scl_low <= 1; phase <= 0; divider <= 0;
                                case (state)
                                    TX_BYTE: begin
                                        if (tx_bit == 0) state <= RX_ACK;
                                        else tx_bit <= tx_bit - 1'b1;
                                    end
                                    RX_ACK: begin
                                        if (sda_sync[1]) begin nack <= 1; state <= STOP; end
                                        else case (tx_stage)
                                            0: begin
                                                tx_shift <= register_select; tx_bit <= 7;
                                                tx_stage <= 1; state <= TX_BYTE;
                                            end
                                            1: state <= RESTART;
                                            default: state <= RX_BYTE;
                                        endcase
                                    end
                                    RX_BYTE: begin
                                        rx_shift <= {rx_shift[14:0], sda_sync[1]};
                                        if (rx_bit == 8 || rx_bit == 0) state <= TX_ACK;
                                        else rx_bit <= rx_bit - 1'b1;
                                    end
                                    TX_ACK: begin
                                        if (rx_bit == 0) state <= STOP;
                                        else begin rx_bit <= 7; state <= RX_BYTE; end
                                    end
                                    default: begin // RECOVER: exactly nine pulses
                                        if (recovery_count == 8) state <= STOP;
                                        else recovery_count <= recovery_count + 1'b1;
                                    end
                                endcase
                            end
                            default: begin state <= STOP; phase <= 0; divider <= 0; end
                        endcase
                    end
                    RESTART: begin
                        case (phase)
                            0: if (elapsed) begin sda_low <= 0; phase <= 1; divider <= 0; end
                            1: if (elapsed) begin scl_low <= 0; phase <= 2; divider <= 0; end
                            2: begin
                                divider <= 0;
                                if (scl_sync[1]) phase <= 3;
                            end
                            3: if (elapsed) begin
                                sda_low <= 1;
                                tx_shift <= {SLAVE_ADDR, 1'b1}; tx_bit <= 7; tx_stage <= 2;
                                state <= START; phase <= 0; divider <= 0;
                            end
                            default: begin state <= STOP; phase <= 0; divider <= 0; end
                        endcase
                    end
                    STOP: begin
                        case (phase)
                            0: if (elapsed) begin sda_low <= 1; phase <= 1; divider <= 0; end
                            1: if (elapsed) begin scl_low <= 0; phase <= 2; divider <= 0; end
                            2: begin
                                divider <= 0;
                                if (scl_sync[1]) phase <= 3;
                            end
                            3: if (elapsed) begin sda_low <= 0; phase <= 4; divider <= 0; end
                            4: begin
                                divider <= 0;
                                if (sda_sync[1] && scl_sync[1]) phase <= 5;
                            end
                            5: begin
                                if (!sda_sync[1] || !scl_sync[1]) divider <= 0;
                                else if (elapsed) begin
                                    phase <= 0; divider <= 0;
                                    if (recovering) begin recovering <= 0; state <= BUS_FREE; end
                                    else begin
                                        busy <= 0; done <= 1; state <= IDLE;
                                        response <= nack ? 16'b0 : rx_shift;
                                    end
                                end
                            end
                            default: begin phase <= 0; divider <= 0; end
                        endcase
                    end
                    default: begin
                        state <= STOP; phase <= 0; divider <= 0; scl_low <= 1;
                    end
                endcase
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (CLK_HZ <= 0 || I2C_HZ <= 0 || I2C_HZ > 1_000_000 || TIMEOUT_MS <= 0)
            $fatal(1, "Invalid I2C Master parameters");
        if (CLK_HZ / I2C_HZ < 20 || SETUP_CYCLES <= 0 || LIMIT <= 0)
            $fatal(1, "Insufficient clock resolution or invalid timeout");
    end
    // synthesis translate_on
endmodule










// `timescale 1ns / 1ps
// // START, address+W, register, repeated START, address+R, MSB, ACK, LSB,
// // NACK, STOP. One open-drain driver per pin; supports clock stretching.
// module i2c_sensor_read_master #(
//     parameter CLK_HZ = 100_000_000,
//     parameter I2C_HZ = 100_000,
//     parameter TIMEOUT_MS = 250,
//     parameter [6:0] SLAVE_ADDR = 7'h42
// )(
//     input clk, reset, start,
//     input [7:0] command,
//     inout sda, scl,
//     output reg busy, done, nack, timeout_error,
//     output reg [15:0] response
// );
//     localparam integer Q = (CLK_HZ+4*I2C_HZ-1)/(4*I2C_HZ);
//     localparam integer LIMIT = (CLK_HZ/1000)*TIMEOUT_MS;
//     localparam  IDLE=0, BUS_FREE=1, START_HOLD=2, START_LOW=3,
//                 TX_SET=4, TX_RISE=5, TX_HIGH=6, TX_FALL=7,
//                 ACK_SET=8, ACK_RISE=9, ACK_HIGH=10, ACK_FALL=11, NEXT_TX=12,
//                 RESTART_LOW=13, RESTART_RISE=14, RESTART_HIGH=15,
//                 RX_SET=16, RX_RISE=17, RX_HIGH=18, RX_FALL=19,
//                 MASTER_ACK_SET=20, MASTER_ACK_RISE=21, MASTER_ACK_HIGH=22,
//                 MASTER_ACK_FALL=23, STOP_SET=24, STOP_RISE=25, STOP_HIGH=26,
//                 STOP_RELEASE=27, STOP_FREE=28, REC_LOW=29, REC_RISE=30,
//                 REC_HIGH=31, REC_FALL=32;
//     reg [5:0] state;
//     reg [31:0] divider, watchdog;
//     reg sda_low, scl_low;
//     reg [7:0] tx_shift, register_select;
//     reg [2:0] tx_bit;
//     reg [3:0] rx_bit, recovery_count;
//     reg [1:0] tx_stage;
//     reg [15:0] rx_shift;
//     reg recovering, recovery_attempted;
//     (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync, scl_sync;
//     assign sda = sda_low ? 1'b0 : 1'bz;
//     assign scl = scl_low ? 1'b0 : 1'bz;
//     always @(posedge clk) begin
//         if (reset) begin sda_sync <= 3; scl_sync <= 3; end
//         else begin sda_sync <= {sda_sync[0],sda}; scl_sync <= {scl_sync[0],scl}; end
//     end
//     always @(posedge clk) begin
//         if (reset) begin
//             state <= IDLE;
//             divider <= 0; watchdog <= 0;
//             sda_low <= 0; scl_low <= 0;
//             busy <= 0; done <= 0;
//             nack <= 0; timeout_error <= 0; response <= 0;
//             tx_shift <= 0; register_select <= 0; tx_bit <= 7; tx_stage <= 0;
//             rx_shift <= 0; rx_bit <= 15; recovery_count <= 0;
//             recovering <= 0; recovery_attempted <= 0;
//         end else begin
//             done <= 0;
//             if (!busy) begin
//                 divider <= 0; watchdog <= 0;
//                 if (start) begin
//                     busy <= 1; nack <= 0; timeout_error <= 0; response <= 0;
//                     register_select <= command;
//                     tx_shift <= {SLAVE_ADDR,1'b0};
//                     tx_stage <= 0; tx_bit <= 7;
//                     rx_bit <= 15; rx_shift <= 0;
//                     recovering <= 0; recovery_attempted <= 0;
//                     state <= BUS_FREE;
//                 end
//             end else if (watchdog >= LIMIT-1) begin
//                 sda_low <= 0; scl_low <= 0;
//                 busy <= 0; done <= 1;
//                 timeout_error <= 1;
//                 response <= 0;
//                 state <= IDLE;
//             end else begin
//                 watchdog <= watchdog+1;
//                 if (divider == Q-1) begin
//                     divider <= 0;
//                     case (state)
//                         BUS_FREE: if (scl_sync[1]) begin
//                             if (sda_sync[1]) begin
//                                 sda_low <= 1;
//                                 state <= START_HOLD;
//                                 end
//                             else if (!recovery_attempted) begin
//                                 recovering <= 1; recovery_attempted <= 1;
//                                 recovery_count <= 0;
//                                 scl_low <= 1;
//                                 state <= REC_LOW;
//                             end
//                         end
//                         START_HOLD: begin
//                             scl_low <= 1;
//                             state <= START_LOW;
//                         end
//                         START_LOW: state <= TX_SET;
//                         TX_SET: begin
//                             sda_low <= !tx_shift[tx_bit];
//                             state <= TX_RISE;
//                             end
//                         TX_RISE: begin scl_low <= 0; state <= TX_HIGH; end
//                         TX_HIGH: if (scl_sync[1]) state <= TX_FALL;
//                         TX_FALL: begin
//                             scl_low <= 1;
//                             if (tx_bit == 0) state <= ACK_SET;
//                             else begin tx_bit <= tx_bit-1; state <= TX_SET; end
//                         end
//                         ACK_SET: begin sda_low <= 0; state <= ACK_RISE; end
//                         ACK_RISE: begin scl_low <= 0; state <= ACK_HIGH; end
//                         ACK_HIGH: if (scl_sync[1]) begin
//                             if (sda_sync[1]) nack <= 1;
//                             state <= ACK_FALL;
//                         end
//                         ACK_FALL: begin scl_low <= 1; state <= NEXT_TX; end
//                         NEXT_TX: if (nack) state <= STOP_SET;
//                             else case (tx_stage)
//                                 0: begin tx_shift <= register_select; tx_bit <= 7; tx_stage <= 1; state <= TX_SET; end
//                                 1: state <= RESTART_LOW;
//                                 default: state <= RX_SET;
//                             endcase
//                         RESTART_LOW: begin sda_low <= 0; state <= RESTART_RISE; end
//                         RESTART_RISE: begin scl_low <= 0; state <= RESTART_HIGH; end
//                         RESTART_HIGH: if (scl_sync[1]) begin
//                             sda_low <= 1; tx_shift <= {SLAVE_ADDR,1'b1};
//                             tx_bit <= 7; tx_stage <= 2; state <= START_HOLD;
//                         end
//                         RX_SET: begin sda_low <= 0; state <= RX_RISE; end
//                         RX_RISE: begin scl_low <= 0; state <= RX_HIGH; end
//                         RX_HIGH: if (scl_sync[1]) begin
//                             rx_shift <= {rx_shift[14:0],sda_sync[1]}; state <= RX_FALL;
//                         end
//                         RX_FALL: begin
//                             scl_low <= 1;
//                             if (rx_bit == 8 || rx_bit == 0) state <= MASTER_ACK_SET;
//                             else begin rx_bit <= rx_bit-1; state <= RX_SET; end
//                         end
//                         MASTER_ACK_SET: begin sda_low <= (rx_bit == 8); state <= MASTER_ACK_RISE; end
//                         MASTER_ACK_RISE: begin scl_low <= 0; state <= MASTER_ACK_HIGH; end
//                         MASTER_ACK_HIGH: if (scl_sync[1]) state <= MASTER_ACK_FALL;
//                         MASTER_ACK_FALL: begin
//                             scl_low <= 1;
//                             if (rx_bit == 0) state <= STOP_SET;
//                             else begin rx_bit <= 7; state <= RX_SET; end
//                         end
//                         STOP_SET: begin sda_low <= 1; state <= STOP_RISE; end
//                         STOP_RISE: begin scl_low <= 0; state <= STOP_HIGH; end
//                         STOP_HIGH: if (scl_sync[1]) state <= STOP_RELEASE;
//                         STOP_RELEASE: begin sda_low <= 0; state <= STOP_FREE; end
//                         STOP_FREE: if (recovering) begin recovering <= 0; state <= BUS_FREE; end
//                             else begin
//                                 busy <= 0; done <= 1; state <= IDLE;
//                                 response <= nack ? 16'b0 : rx_shift;
//                             end
//                         REC_LOW: begin sda_low <= 0; scl_low <= 1; state <= REC_RISE; end
//                         REC_RISE: begin scl_low <= 0; state <= REC_HIGH; end
//                         REC_HIGH: if (scl_sync[1]) state <= REC_FALL;
//                         REC_FALL: begin
//                             scl_low <= 1;
//                             if (recovery_count == 8) state <= STOP_SET;
//                             else begin recovery_count <= recovery_count+1; state <= REC_LOW; end
//                         end
//                         default: state <= STOP_SET;
//                     endcase
//                 end else divider <= divider+1;
//             end
//         end
//     end
// endmodule
