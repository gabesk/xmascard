`timescale 1ns / 1ps
module lights(
    input clk,
    input rx,
    output tx,
    output [2*12-1:0] leds
    );

    wire clk_uart;    
    uart_clk uart_clk_i(.CLKIN_IN(clk), 
                        .CLKFX_OUT(clk_uart), 
                        .CLKIN_IBUFG_OUT(), 
                        .CLK0_OUT());

    wire rx_i;
    reg [4:0] rx_sync = 0;
    always @ (posedge clk_uart) rx_sync <= {rx_sync[3:0], rx};
    assign rx_i = rx_sync[4];
    
    // ~30 fps animation at 25 Mhz clk means need 21 bit advance counter using
    // top bit as program advance clock. This gives ~ 11 Hz.
    reg [26:0] clk_div; initial clk_div = 0;
    always @ (posedge clk_uart) clk_div <= clk_div + 1;
    wire clk_step = clk_div[17];

    reg clk_step_l; initial clk_step_l = 0;
    always @ (posedge clk_uart) clk_step_l <= clk_step;

    reg step; initial step = 0;

    always @ (posedge clk_uart)
        if (clk_step && ~clk_step_l)    step <= 1;
        else                            step <= 0;

    wire [7:0] pwm_counter = clk_div[13:6]; // 191 Hz
    wire [71:0] leds_p, leds_r, leds_i;
    reg [71:0] leds_mux;
    
    wire [7:0] pat_up_a;
    wire [71:0] pat_up_d;
    wire pat_up_we;

    wire [1:0] pattern_type; // 0: free running, 1: stored pattern, 2: random, 3: individual LEDs

    led specific_leds[11:0](
        .pwm_counter(pwm_counter),
        .values(leds_mux),
        .leds(leds)
    );

    stored_pattern p(clk_uart, step, pat_up_a, pat_up_d, pat_up_we, leds_p);
    random r(clk_uart, step, pwm_counter, leds_r);
    serial s(clk_uart, rx_i, tx, pat_up_a, pat_up_d, pat_up_we, pattern_type, leds_i);
    wire clk_switch = clk_div[26];
    always @ (*)
        case (pattern_type)
            0: begin
                case(clk_switch)
                    0: leds_mux <= leds_p;
                    1: leds_mux <= leds_r;
                endcase
            end
            1: leds_mux <= leds_p;
            2: leds_mux <= leds_r;
            3: leds_mux <= leds_i;
        endcase
endmodule

module random(
    input clk,
    input step,
    input [7:0] pwm_counter,
    output [71:0] leds
    );

    reg [23:0] initializer = 24'hffffff;
    always @ (posedge clk)
        if (initializer) if (pwm_counter[2]) initializer <= {initializer[22:0], 1'b0};

    random_led l[11:0](
        .clk({12{clk}}),
        .rst(initializer),
        .step({12{step}}),
        .values(leds)
    );
endmodule

module random_led(
    input clk,
    input [1:0] rst,
    input step,
    output [5:0] values);

    twinkler each_color[1:0](.clk({2{clk}}),
                             .rst(rst),
                             .step({2{step}}),
                             .signal(values));
endmodule

module lfsr3(input clk, input step, input rst, output value);
    reg [7:0] lfsr = 0;
    wire feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    always @ (posedge clk)
        if (rst)       lfsr <= lfsr + 1;
        else if (step) lfsr <= {lfsr[6:0], feedback};
    assign value = lfsr[7] & lfsr[6] & lfsr[5] & lfsr[4] & lfsr[3];
endmodule

module twinkler(
    input clk,
    input rst,
    input step,
    output [2:0] signal);

    wire go;
    lfsr3 rng(.clk(clk), .step(step), .rst(rst), .value(go));

    reg [2:0] intensity = 0;
    assign signal = intensity;
    reg direction = 0;
    reg state; initial state = 0;
    always @ (posedge clk) begin
        case (state)
            0: if (go) state <= 1;
            1: begin
                case (direction)
                    0: begin
                        if (step) begin
                            intensity <= intensity + 1;
                            if (intensity == 3'b110) direction <= 1;
                        end
                    end
                    1: begin
                        if (step) begin
                            intensity <= intensity - 1;
                            if (intensity == 3'b001) begin
                                direction <= 0;
                                state <= 0;
                            end
                        end
                    end
                endcase
            end
        endcase
    end
endmodule

module stored_pattern(
    input clk,
    input step,
    input [7:0] pat_up_a,
    input [71:0] pat_up_d,
    input pat_up_we,
    output [71:0] leds
    );
    
    wire [71:0] led_values;
    assign leds = led_values;
    reg [7:0] prog_addr = 0;

    // 12 LEDs. 8 bits of color per LED; 4 bits per color. 96 bits per program
    // step. BRAMs have 256 x 72 at their widest. Could we reduce the colors so
    // that each BRAM load contains an entire program? Well ... if so, there
    // would be 6 bits per LED. That would be 8 shades per color. That might be
    // ok given this is a V1 product.
    
    ram72bit pattern_ram (
      .clka(clk), // input clka
      .wea(pat_up_we), // input [0 : 0] wea
      .addra(pat_up_we ? pat_up_a : prog_addr), // input [7 : 0] addra
      .dina(pat_up_d), // input [71 : 0] dina
      .douta(led_values) // output [71 : 0] douta
    );
    
    always @ (posedge clk) if (step) prog_addr <= prog_addr + 1;

    reg [16:0] clk_div; initial clk_div = 0;
    always @ (posedge clk) clk_div <= clk_div + 1;

endmodule

module led(
    input [7:0] pwm_counter,
    // Red, green, with green LSBs.
    input [5:0] values,
    output [1:0] leds
);

    pwm pwms[1:0](
        .counter({2{pwm_counter}}),
        .value(values),
        .signal(leds)
    );

endmodule

module pwm(
    input [7:0] counter,
    input [2:0] value,
    output reg signal
);

    reg [7:0] counter_value;
    always @ (*) begin
        case (value)
            0: counter_value <= 0;
            1: counter_value <= 15;
            2: counter_value <= 35;
            3: counter_value <= 63;
            4: counter_value <= 99;
            5: counter_value <= 143;
            6: counter_value <= 195;
            7: counter_value <= 255;
        endcase
    end
    // Generate PWM signal
    always @ (*) begin
        signal <= (counter_value > counter);
    end

endmodule
