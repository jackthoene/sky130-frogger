/*
 * Copyright (c) 2026 Jack Thoene
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_jackthoene_frogger (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // pixel clock (~25.175 MHz for 640x480@60)
    input  wire       rst_n     // reset_n - low to reset
);

  // ---------------------------------------------------------------------------
  // Gamepad PMOD interface (Psychogenic gamepad-pmod, TT default pinout)
  // ---------------------------------------------------------------------------
  wire pmod_latch = ui_in[4];
  wire pmod_clk_i = ui_in[5];
  wire pmod_data  = ui_in[6];

  wire btn_b, btn_y, btn_select, btn_start;
  wire btn_up, btn_down, btn_left, btn_right;
  wire btn_a, btn_x, btn_l, btn_r;
  wire gamepad_present;

  gamepad_pmod_single gamepad (
      .rst_n     (rst_n),
      .clk       (clk),
      .pmod_data (pmod_data),
      .pmod_clk  (pmod_clk_i),
      .pmod_latch(pmod_latch),
      .b         (btn_b),
      .y         (btn_y),
      .select    (btn_select),
      .start     (btn_start),
      .up        (btn_up),
      .down      (btn_down),
      .left      (btn_left),
      .right     (btn_right),
      .a         (btn_a),
      .x         (btn_x),
      .l         (btn_l),
      .r         (btn_r),
      .is_present(gamepad_present)
  );

  // ---------------------------------------------------------------------------
  // VGA timing (640x480@60 standard)
  // ---------------------------------------------------------------------------
  wire hsync, vsync, display_on;
  wire [9:0] hpos, vpos;

  hvsync_generator vga (
      .clk       (clk),
      .reset     (~rst_n),
      .hsync     (hsync),
      .vsync     (vsync),
      .display_on(display_on),
      .hpos      (hpos),
      .vpos      (vpos)
  );

  // ---------------------------------------------------------------------------
  // Frog sprite — 16x16 square, moved one tile per frame on held d-pad input.
  // Frame edge detected at vpos==0,hpos==0; a 4-bit counter throttles motion.
  // ---------------------------------------------------------------------------
  localparam [9:0] FROG_SIZE   = 10'd16;
  localparam [9:0] FROG_X_MAX  = 10'd624;  // 640 - 16
  localparam [9:0] FROG_Y_MAX  = 10'd464;  // 480 - 16

  reg [9:0] frog_x;
  reg [9:0] frog_y;
  reg [3:0] step_div;
  wire frame_tick = (hpos == 10'd0) && (vpos == 10'd0);
  wire move_tick  = frame_tick && (step_div == 4'd0);

  always @(posedge clk) begin
    if (~rst_n) begin
      frog_x   <= 10'd312;       // start near horizontal center
      frog_y   <= FROG_Y_MAX;    // start at the bottom (grass)
      step_div <= 4'd0;
    end else if (frame_tick) begin
      step_div <= step_div + 4'd1;
      if (move_tick) begin
        if (btn_up    && frog_y >= FROG_SIZE)    frog_y <= frog_y - FROG_SIZE;
        if (btn_down  && frog_y <  FROG_Y_MAX)   frog_y <= frog_y + FROG_SIZE;
        if (btn_left  && frog_x >= FROG_SIZE)    frog_x <= frog_x - FROG_SIZE;
        if (btn_right && frog_x <  FROG_X_MAX)   frog_x <= frog_x + FROG_SIZE;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Renderer — three horizontal bands (water/road/grass) plus the frog sprite
  // ---------------------------------------------------------------------------
  wire frog_hit = (hpos >= frog_x) && (hpos < frog_x + FROG_SIZE) &&
                  (vpos >= frog_y) && (vpos < frog_y + FROG_SIZE);

  wire in_water = (vpos < 10'd160);
  wire in_road  = (vpos >= 10'd160) && (vpos < 10'd320);

  reg [1:0] R, G, B;
  always @(*) begin
    if (!display_on) begin
      {R, G, B} = 6'b00_00_00;
    end else if (frog_hit) begin
      {R, G, B} = 6'b00_11_00;     // bright green frog
    end else if (in_water) begin
      {R, G, B} = 6'b00_00_10;     // dark blue water
    end else if (in_road) begin
      {R, G, B} = 6'b01_01_01;     // gray road
    end else begin
      {R, G, B} = 6'b00_10_00;     // dark green grass
    end
  end

  // ---------------------------------------------------------------------------
  // TT VGA Pmod pinout
  // ---------------------------------------------------------------------------
  assign uo_out[0] = R[1];
  assign uo_out[1] = G[1];
  assign uo_out[2] = B[1];
  assign uo_out[3] = vsync;
  assign uo_out[4] = R[0];
  assign uo_out[5] = G[0];
  assign uo_out[6] = B[0];
  assign uo_out[7] = hsync;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  wire _unused = &{ena, ui_in[3:0], ui_in[7], uio_in,
                   btn_b, btn_y, btn_select, btn_start,
                   btn_a, btn_x, btn_l, btn_r,
                   gamepad_present, 1'b0};

endmodule
