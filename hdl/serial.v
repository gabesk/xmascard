`timescale 1ns / 1ps
module serial(
    input clk_uart,
    input rx,
    output tx,
    output [7:0] a,
    output [71:0] d,
    output we,
    output [1:0] pattern_type, // 0: free running, 1: stored pattern, 2: random, 3: individual LEDs
    output [71:0] specific_led_values
    );
    
    wire done, rdy, xmit, busy;
    wire [7:0] rxd;
    wire [7:0] txd;

    wire tick_8x;
    uart_clk_synth u(clk_uart, tick_8x);
  
    tx t(.clk(clk_uart),
         .tick_8x(tick_8x),
         .xmit_data(xmit),
         .txd(txd),
         .tx(tx),
         .done(done),
         .busy(busy),
         .error());

    rx r(.clk(clk_uart),
         .tick_8x(tick_8x),
         .rx(rx),
         .data_received(rdy),
         .rxd(rxd));
         
    new_pattern statem(clk_uart,
                       rxd, 
                       rdy, 
                       txd, 
                       xmit, 
                       busy, 
                       a, 
                       d, 
                       we, 
                       pattern_type, 
                       specific_led_values);

endmodule

module new_pattern(
    input clk,
    input [7:0] rxd,
    input data_received,
    output reg [7:0] txd = 0,
    output reg xmit = 0,
    input busy,
    output reg [7:0] a = 0,
    output reg [71:0] d = 0,
    output reg we = 0,
    output reg [1:0] mode = 0,
    output reg [71:0] individual_leds = 0
    );

    reg [4:0] led = 0;
    reg [2:0] led_brightness = 0;
    
    integer s = 0;
    `define RESET 0
    `define RECEIVE_ADDR 1
    `define RECEIVE_DATA 2
    `define READBACK (`RECEIVE_DATA + 9)
    `define SWITCH_MODE (`READBACK + 11)
    `define INDIVIDUAL_LEDS (`SWITCH_MODE + 1)
    always @ (posedge clk) begin
        xmit <= 0;
        we <= 0;
        case (s)
            `RESET: if (data_received) begin
                case (rxd)
                    "w":        s <= `RECEIVE_ADDR;
                    "m":        s <= `SWITCH_MODE;
                    "i":        s <= `INDIVIDUAL_LEDS;
                    default:    s <= `RESET;
                endcase
            end

            // Update stored pattern RAM
            `RECEIVE_ADDR:      if (data_received) begin a <= rxd; s <= s + 1; end
            `RECEIVE_DATA:      if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 1:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 2:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 3:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 4:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 5:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 6:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 7:  if (data_received) begin d <= {d[63:0], rxd}; s <= s + 1; end
            `RECEIVE_DATA + 8:  if (data_received) begin d <= {d[63:0], rxd}; txd <= "o"; xmit <= 1; we <= 1; s <= `READBACK; end
            
            `READBACK:          if (!busy) begin txd <= a;          xmit <= 1; s <= s + 1; end
            `READBACK + 1:      if (!busy) begin txd <= d[71:64];   xmit <= 1; s <= s + 1; end
            `READBACK + 2:      if (!busy) begin txd <= d[63:56];   xmit <= 1; s <= s + 1; end
            `READBACK + 3:      if (!busy) begin txd <= d[55:48];   xmit <= 1; s <= s + 1; end
            `READBACK + 4:      if (!busy) begin txd <= d[47:40];   xmit <= 1; s <= s + 1; end
            `READBACK + 5:      if (!busy) begin txd <= d[39:32];   xmit <= 1; s <= s + 1; end
            `READBACK + 6:      if (!busy) begin txd <= d[31:24];   xmit <= 1; s <= s + 1; end
            `READBACK + 7:      if (!busy) begin txd <= d[23:16];   xmit <= 1; s <= s + 1; end
            `READBACK + 8:      if (!busy) begin txd <= d[15:8];    xmit <= 1; s <= s + 1; end
            `READBACK + 9:      if (!busy) begin txd <= d[7:0];     xmit <= 1; s <= s + 1; end
            `READBACK +10:      if (!busy) begin txd <= "d";        xmit <= 1; s <= `RESET; end

            // Change mode
            `SWITCH_MODE:       if (data_received) begin mode <= rxd; txd <= rxd; xmit <= 1; s <= `RESET; end
            
            // Set an individual LED. Note that this doesn't have any effect unless the mode is switched to it at some point
            `INDIVIDUAL_LEDS:   if (data_received) begin led <= rxd; s <= s + 1; end
            `INDIVIDUAL_LEDS+1: if (data_received) begin led_brightness <= rxd; txd <= led; xmit <= 1; s <= s + 1; end
            `INDIVIDUAL_LEDS+2: if (!busy) begin
                                                         txd <= led_brightness;
                                                         // update just the specified LED in the array of LEDs
                                                         individual_leds <= (individual_leds & (~(3'b111 << (led*3)))) | (led_brightness << (led*3));
                                                         xmit <= 1;
                                                         s <= `RESET;
                                           end
        endcase
    end

endmodule

`define RESET_TYPE_ZEROS 0
`define RESET_TYPE_HALF 1

module rx(
    input clk,
    input tick_8x,
    input rx,
    output reg [7:0] rxd = 0,
    output reg data_received = 0
    );

    // Divide the incoming clock by baud rate of the serial port.
    wire go;
    reg rst_clk_cnt = 0;
    clk_div #(.RESET_TYPE(`RESET_TYPE_HALF)) clk_div_i(clk, tick_8x, rst_clk_cnt, go);

    reg [7:0] rxd_shift = 0;
    reg [3:0] receive_cnt = 0;
    always @ (posedge clk) begin
        data_received <= 0;
        rst_clk_cnt <= 0;
        if (receive_cnt == 1) begin
            // Wait for high value to reset for next bit.
            if (rx) receive_cnt <= 0;
        end else if (receive_cnt) begin
            // In the middle of receiving a transmission. Wait for go and shift
            // in a data bit.
            if (go) begin
                rxd_shift <= {rx, rxd_shift[7:1]};
                receive_cnt <= receive_cnt - 1;
                // If this is the last bit, then we're done. However, at this
                // point it is in the middle of the last bit, which could be
                // low. If the state machine is simply reset at this point, this
                // bit would be mistaken for a new start bit. Instead, wait for
                // a high signal value before resetting.
                if (receive_cnt == 2) begin
                    data_received <= 1;
                    rxd <= rxd_shift;
                end
            end
        end else begin
            // Wait for the start bit.
            if (!rx) begin
                rst_clk_cnt <= 1;
                receive_cnt <= 11;
            end
        end
    end
endmodule

module tx(
    input clk,
    input tick_8x,
    input [7:0] txd,
    input xmit_data,
    output reg done = 0,
    output busy,
    output tx,
    output reg error = 0
    );
    
    // Divide the incoming clock by baud rate of the serial port.
    wire go;
    reg rst_clk_cnt = 0;
    clk_div #(.RESET_TYPE(`RESET_TYPE_ZEROS)) clk_div_i(clk, tick_8x, rst_clk_cnt, go);

    reg transmitting = 0;
    reg [9:0] txd_shift = 10'b1111111111;
    assign tx = txd_shift[0];
    reg [3:0] xmit_cnt = 0;
    assign busy = xmit_data || (xmit_cnt != 0);
    always @ (posedge clk) begin
        rst_clk_cnt <= 0;
        done <= 0;
        // Wait for the go signal.
        if (xmit_data) begin
            transmitting <= 1;
            rst_clk_cnt <= 1;
            xmit_cnt <= 10;
            txd_shift <= {1'b1, txd, 1'b0};
        end else if (xmit_cnt) begin
            if (go) begin
                txd_shift <= {1'b1, txd_shift[9:1]};
                xmit_cnt <= xmit_cnt - 1;
                // If this is the last bit, then we're done.
                if (xmit_cnt == 1) begin
                    transmitting <= 0;
                    done <= 1;
                    // Allow a new transmission to start as soon as the old one
                    // finishes.
                    if (xmit_data) begin
                        transmitting <= 1;
                        rst_clk_cnt <= 1;
                        xmit_cnt <= 10;
                        txd_shift <= {1'b1, txd, 1'b0};
                    end 
                end
            end
        end
    end

    always @ (posedge clk) begin
        error <= 0;
        if (xmit_data) begin
            // When is it ok to request a transmission?
            // 1. When transmitting == FALSE
            // 2. When go && xmit_cnt == 1
            if (!transmitting) begin
                // This is ok
            end else if (go && xmit_cnt == 1) begin
                // This is also ok.
            end else begin
                error <= 1;
            end
        end
    end
endmodule

module uart_clk_synth(
    input clk,
    output reg uart_8x_tick = 0
    );

    reg [2:0] clk_div = 0;

    always @ (posedge clk) begin
        clk_div <= clk_div + 1;
        uart_8x_tick <= 0;
        if (clk_div == 6) begin
            clk_div <= 0;
            uart_8x_tick <= 1;
        end
    end
endmodule

module clk_div(
    input clk,
    input tick_8x,
    input rst,
    output go
    );
    parameter RESET_TYPE = 0; // 0 - full, 1 - half

    reg [2:0] clk_div = 0;
    always @ (posedge clk) begin
        if (rst) begin
            if (RESET_TYPE == 0) begin
                clk_div <= 0;
            end else begin
                // Init the clock divider to half such that the go signal
                // happens midway through a received data bit.
                clk_div <= 4;
            end
        end else if (tick_8x) begin 
            clk_div <= clk_div + 1;
        end
    end

    assign go = !rst & tick_8x & clk_div == 3'b111;
endmodule