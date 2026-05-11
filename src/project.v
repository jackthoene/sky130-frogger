/*
 * "Frogge" — Frogger for Tiny Tapeout / VGA Playground
 * =====================================================
 * A hardware Frogger clone: dodge cars, ride logs, fill goal slots.
 *
 * Target: VGA Playground (https://vga-playground.com/)
 *         Tiny Tapeout TTSKY26a demoscene competition (1 tile)
 *
 * Controls (Gamepad Pmod on ui_in[6:4]):
 *   D-Pad  — hop up/down/left/right (one hop per press)
 *   Start  — restart game
 *
 * Fallback (ui_in buttons when no gamepad):
 *   ui_in[0]=Up  ui_in[1]=Down  ui_in[2]=Left  ui_in[3]=Right
 *
 * VGA Output (Tiny VGA Pmod on uo_out[7:0]):
 *   uo_out = {hsync, B0, G0, R0, vsync, B1, G1, R1}
 *
 * Audio Output (TT Audio Pmod on uio[7]):
 *   Hop blip, splash/death buzz, goal chime
 *
 * Layout (15 rows × 32 pixels = 480):
 *   Row 0-1 : Score / lives header
 *   Row 2   : Goal zone (5 lily-pad slots)
 *   Row 3-5 : River lanes (logs on water)
 *   Row 6   : Safe median (grass)
 *   Row 7-9 : Road lanes (cars)
 *   Row 10-14: Start area (grass)
 *
 * No multipliers. No dividers. No RAM. Pure combinational frog.
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_jackthoene_frogger (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Bidirectional IOs: audio on uio[7]
    assign uio_oe  = 8'b1000_0000;
    assign uio_out = {audio_out, 7'b0000000};

    // =====================================================================
    // VGA timing (640×480 @ ~25 MHz)
    // =====================================================================
    wire hsync, vsync, display_on;
    wire [9:0] pix_x, pix_y;

    hvsync_generator hvsync_gen (
        .clk(clk), .reset(~rst_n),
        .hsync(hsync), .vsync(vsync),
        .display_on(display_on),
        .hpos(pix_x), .vpos(pix_y)
    );

    // =====================================================================
    // Gamepad Pmod
    // =====================================================================
    wire gp_start;
    wire gp_up, gp_down, gp_left, gp_right;
    wire gp_present;
    /* verilator lint_off PINCONNECTEMPTY */
    gamepad_pmod_single gamepad (
        .rst_n(rst_n), .clk(clk),
        .pmod_data(ui_in[6]), .pmod_clk(ui_in[5]), .pmod_latch(ui_in[4]),
        .is_present(gp_present),
        .b(), .y(), .select(), .start(gp_start),
        .up(gp_up), .down(gp_down), .left(gp_left), .right(gp_right),
        .a(), .x(), .l(), .r()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // Merged input (gamepad priority, ui_in fallback)
    wire btn_up    = gp_present ? gp_up    : ui_in[0];
    wire btn_down  = gp_present ? gp_down  : ui_in[1];
    wire btn_left  = gp_present ? gp_left  : ui_in[2];
    wire btn_right = gp_present ? gp_right : ui_in[3];
    wire btn_start = gp_present ? gp_start : 1'b0;

    // Edge detect → one hop per press
    reg [3:0] btn_prev;
    wire [3:0] btn_cur = {btn_right, btn_left, btn_down, btn_up};
    wire hop_up    = btn_cur[0] & ~btn_prev[0];
    wire hop_down  = btn_cur[1] & ~btn_prev[1];
    wire hop_left  = btn_cur[2] & ~btn_prev[2];
    wire hop_right = btn_cur[3] & ~btn_prev[3];

    // Frame tick (vsync falling edge ≈ 60 Hz)
    reg vsync_prev;
    wire frame_tick = ~vsync & vsync_prev;
    always @(posedge clk) begin
        if (~rst_n) vsync_prev <= 1'b0;
        else        vsync_prev <= vsync;
    end

    // Update btn_prev only once per frame so hop edges stay
    // high until the game logic consumes them on frame_tick
    always @(posedge clk) begin
        if (~rst_n)          btn_prev <= 4'd0;
        else if (frame_tick) btn_prev <= btn_cur;
    end

    // =====================================================================
    // Lane scroll offsets (individual regs — no arrays for max compat)
    //   road0-2 → top_rows 7-9     river0-2 → top_rows 3-5
    // =====================================================================
    reg [6:0] road0, road1, road2;
    reg [6:0] river0, river1, river2;

    always @(posedge clk) begin
        if (~rst_n) begin
            road0 <= 7'd0; road1 <= 7'd0; road2 <= 7'd0;
            river0 <= 7'd0; river1 <= 7'd0; river2 <= 7'd0;
        end else if (frame_tick) begin
            // Road:  different speeds & directions
            road0  <= road0  + 7'd1;   // → slow
            road1  <= road1  - 7'd2;   // ← medium
            road2  <= road2  + 7'd3;   // → fast
            // River: logs drift
            river0 <= river0 + 7'd1;   // → slow
            river1 <= river1 - 7'd2;   // ← medium
            river2 <= river2 + 7'd2;   // → medium
        end
    end

    // =====================================================================
    // Row geometry (each row = 32 px, top_row = pix_y[8:5])
    // =====================================================================
    wire [3:0] top_row    = pix_y[8:5];       // 0-14
    wire [4:0] row_local  = pix_y[4:0];       // 0-31 within row
    wire       is_header  = (top_row <= 4'd1);
    wire       is_goal    = (top_row == 4'd2);
    wire       is_river   = (top_row >= 4'd3) && (top_row <= 4'd5);
    wire       is_median  = (top_row == 4'd6);
    wire       is_road    = (top_row >= 4'd7) && (top_row <= 4'd9);
    wire       is_grass   = (top_row >= 4'd10);

    // =====================================================================
    // Obstacle / log rendering for current pixel
    // Select lane offset, period=128 (mask=7'h7F), varying widths
    // =====================================================================
    reg [6:0] pix_lane_off;
    reg [6:0] pix_obs_w;

    always @(*) begin
        pix_lane_off = 7'd0;
        pix_obs_w    = 7'd0;
        case (top_row)
            4'd7:  begin pix_lane_off = road0;  pix_obs_w = 7'd40; end
            4'd8:  begin pix_lane_off = road1;  pix_obs_w = 7'd32; end
            4'd9:  begin pix_lane_off = road2;  pix_obs_w = 7'd28; end
            4'd3:  begin pix_lane_off = river0; pix_obs_w = 7'd60; end
            4'd4:  begin pix_lane_off = river1; pix_obs_w = 7'd50; end
            4'd5:  begin pix_lane_off = river2; pix_obs_w = 7'd64; end
            default: ;
        endcase
    end

    wire [6:0] pix_lane_pos = pix_x[6:0] + pix_lane_off;
    wire       pix_has_obj  = (pix_lane_pos < pix_obs_w);

    // =====================================================================
    // Game state
    // =====================================================================
    localparam S_PLAY = 2'd0, S_DEAD = 2'd1, S_WIN = 2'd2, S_OVER = 2'd3;

    reg  [1:0]  state;
    reg  [9:0]  frog_x;       // pixel X (0-616)
    reg  [3:0]  frog_row;     // top_row index (2=goal … 12=start)
    reg  [2:0]  lives;
    reg  [2:0]  score;        // max 5 (win triggers reset)
    reg  [5:0]  anim_timer;
    reg  [4:0]  goal_slots;   // 5 home slots

    // Frog pixel-Y from row index
    wire [9:0] frog_y = {frog_row, 5'b00000} + 10'd4; // centered in 32-px row
    wire [9:0] frog_cx = frog_x + 10'd12;

    // Collision: which lane is the frog in?
    reg  [6:0] frog_off;
    reg  [6:0] frog_obs_w;

    always @(*) begin
        frog_off   = 7'd0;
        frog_obs_w = 7'd0;
        case (frog_row)
            4'd7:  begin frog_off = road0;  frog_obs_w = 7'd40; end
            4'd8:  begin frog_off = road1;  frog_obs_w = 7'd32; end
            4'd9:  begin frog_off = road2;  frog_obs_w = 7'd28; end
            4'd3:  begin frog_off = river0; frog_obs_w = 7'd60; end
            4'd4:  begin frog_off = river1; frog_obs_w = 7'd50; end
            4'd5:  begin frog_off = river2; frog_obs_w = 7'd64; end
            default: ;
        endcase
    end

    wire [6:0] frog_lp      = frog_cx[6:0] + frog_off;
    // Generous hitbox: 8px grace on each side of the log
    wire       frog_on_obj  = (frog_lp < frog_obs_w + 7'd8) || (frog_lp >= 7'd120);
    wire       frog_in_road = (frog_row >= 4'd7)  && (frog_row <= 4'd9);
    wire       frog_in_rivr = (frog_row >= 4'd3)  && (frog_row <= 4'd5);
    wire       frog_at_goal = (frog_row == 4'd2);

    // River carry speed (signed, per lane)
    reg signed [3:0] carry_spd;
    always @(*) begin
        carry_spd = 4'sd0;
        case (frog_row)
            4'd3: carry_spd = -4'sd1;  // river0 offset += 1 → logs drift left
            4'd4: carry_spd =  4'sd2;  // river1 offset -= 2 → logs drift right
            4'd5: carry_spd = -4'sd2;  // river2 offset += 2 → logs drift left
            default: carry_spd = 4'sd0;
        endcase
    end

    // Goal-slot index from frog X (5 zones of 128 px)
    wire [2:0] g_slot = frog_cx[9:7];

    // Safe check on goal_slots with explicit mux
    reg goal_already_filled;
    always @(*) begin
        case (g_slot)
            3'd0: goal_already_filled = goal_slots[0];
            3'd1: goal_already_filled = goal_slots[1];
            3'd2: goal_already_filled = goal_slots[2];
            3'd3: goal_already_filled = goal_slots[3];
            3'd4: goal_already_filled = goal_slots[4];
            default: goal_already_filled = 1'b1; // treat as full
        endcase
    end

    // =====================================================================
    // Game logic (runs each frame)
    // =====================================================================
    // Sound trigger flags
    reg snd_hop, snd_die, snd_goal;

    always @(posedge clk) begin
        if (~rst_n || btn_start) begin
            state      <= S_PLAY;
            frog_x     <= 10'd308;
            frog_row   <= 4'd13;
            lives      <= 3'd3;
            score      <= 3'd0;
            anim_timer <= 6'd0;
            goal_slots <= 5'b00000;
            snd_hop    <= 1'b0;
            snd_die    <= 1'b0;
            snd_goal   <= 1'b0;
        end else begin
            snd_hop  <= 1'b0;
            snd_die  <= 1'b0;
            snd_goal <= 1'b0;

            if (frame_tick) begin
                case (state)
                // ---- PLAYING ----
                S_PLAY: begin
                    // Hop movement (edge-triggered, one row/24 px per press)
                    if (hop_up && frog_row > 4'd2) begin
                        frog_row <= frog_row - 4'd1;
                        snd_hop  <= 1'b1;
                    end
                    if (hop_down && frog_row < 4'd14) begin
                        frog_row <= frog_row + 4'd1;
                        snd_hop  <= 1'b1;
                    end
                    if (hop_left && frog_x >= 10'd24) begin
                        frog_x  <= frog_x - 10'd24;
                        snd_hop <= 1'b1;
                    end
                    if (hop_right && frog_x <= 10'd592) begin
                        frog_x  <= frog_x + 10'd24;
                        snd_hop <= 1'b1;
                    end

                    // River carry (frog drifts with log)
                    if (frog_in_rivr && frog_on_obj)
                        frog_x <= frog_x + {{6{carry_spd[3]}}, carry_spd};

                    // --- Collisions ---
                    // Hit a car
                    if (frog_in_road && frog_on_obj) begin
                        state      <= S_DEAD;
                        anim_timer <= 6'd40;
                        snd_die    <= 1'b1;
                    end
                    // Fell in water (on river but not on log)
                    if (frog_in_rivr && ~frog_on_obj) begin
                        state      <= S_DEAD;
                        anim_timer <= 6'd40;
                        snd_die    <= 1'b1;
                    end
                    // Carried off-screen
                    if (frog_x > 10'd620) begin
                        state      <= S_DEAD;
                        anim_timer <= 6'd40;
                        snd_die    <= 1'b1;
                    end

                    // Reached goal
                    if (frog_at_goal) begin
                        snd_goal <= 1'b1;
                        if (g_slot < 3'd5 && ~goal_already_filled) begin
                            case (g_slot)
                                3'd0: goal_slots[0] <= 1'b1;
                                3'd1: goal_slots[1] <= 1'b1;
                                3'd2: goal_slots[2] <= 1'b1;
                                3'd3: goal_slots[3] <= 1'b1;
                                3'd4: goal_slots[4] <= 1'b1;
                            endcase
                            score <= score + 3'd1;
                        end
                        // Frog returns to start
                        frog_x   <= 10'd308;
                        frog_row <= 4'd13;
                        // All 5 filled?
                        if ((goal_slots | (5'b00001 << g_slot)) == 5'b11111) begin
                            state      <= S_WIN;
                            anim_timer <= 6'd60;
                        end
                    end
                end

                // ---- DEATH ANIMATION ----
                S_DEAD: begin
                    if (anim_timer > 6'd0)
                        anim_timer <= anim_timer - 6'd1;
                    else begin
                        if (lives > 3'd1) begin
                            lives    <= lives - 3'd1;
                            frog_x   <= 10'd308;
                            frog_row <= 4'd13;
                            state    <= S_PLAY;
                        end else begin
                            lives <= 3'd0;
                            state <= S_OVER;
                        end
                    end
                end

                // ---- WIN (all slots filled) ----
                S_WIN: begin
                    if (anim_timer > 6'd0)
                        anim_timer <= anim_timer - 6'd1;
                    else begin
                        goal_slots <= 5'b00000;
                        frog_x     <= 10'd308;
                        frog_row   <= 4'd13;
                        state      <= S_PLAY;
                    end
                end

                // ---- GAME OVER (press Start to restart) ----
                S_OVER: ; // held until rst_n / btn_start
                endcase
            end
        end
    end

    // =====================================================================
    // Frog sprite (24×24 with eyes, belly, legs)
    // =====================================================================
    wire [9:0] fdx = pix_x - frog_x;
    wire [9:0] fdy = pix_y - frog_y;
    wire in_frog   = (fdx < 10'd24) && (fdy < 10'd24);
    // Blink frog during death animation
    wire show_frog = in_frog && (state != S_DEAD || anim_timer[2]) && (state != S_OVER);

    // Sub-sprite regions (eye dots, 4×4 each at the top corners)
    wire feye_l  = (fdx[4:2] == 3'b001) && (fdy[4:2] == 3'b001);
    wire feye_r  = (fdx[4:2] == 3'b100) && (fdy[4:2] == 3'b001);

    // =====================================================================
    // Road decorations
    // =====================================================================
    wire road_stripe = (row_local >= 5'd15) && (row_local <= 5'd16) && pix_x[4];

    // =====================================================================
    // Goal-zone rendering
    // =====================================================================
    wire [2:0] gz_slot = pix_x[9:7]; // which of 5 slots
    wire in_pad = (gz_slot < 3'd5) &&
                  (pix_x[6:0] >= 7'd24) && (pix_x[6:0] < 7'd104) &&
                  (row_local >= 5'd4) && (row_local < 5'd28);
    reg gz_filled;
    always @(*) begin
        case (gz_slot)
            3'd0: gz_filled = goal_slots[0];
            3'd1: gz_filled = goal_slots[1];
            3'd2: gz_filled = goal_slots[2];
            3'd3: gz_filled = goal_slots[3];
            3'd4: gz_filled = goal_slots[4];
            default: gz_filled = 1'b0;
        endcase
    end

    // =====================================================================
    // Water shimmer (cheap XOR pattern, no extra register taps)
    // =====================================================================
    wire sparkle = &pix_x[2:0] & ~pix_y[1];

    // =====================================================================
    // Header: lives (green squares) + score (white bar)
    // =====================================================================
    wire life1 = is_header && (row_local >= 5'd10) && (row_local < 5'd20)
                 && (pix_x >= 10'd8)  && (pix_x < 10'd24)  && (lives >= 3'd1);
    wire life2 = is_header && (row_local >= 5'd10) && (row_local < 5'd20)
                 && (pix_x >= 10'd28) && (pix_x < 10'd44)  && (lives >= 3'd2);
    wire life3 = is_header && (row_local >= 5'd10) && (row_local < 5'd20)
                 && (pix_x >= 10'd48) && (pix_x < 10'd64)  && (lives >= 3'd3);
    wire show_life = life1 | life2 | life3;

    // Score bar: 5 cells of 32 px at pix_x in [480, 640)
    //   pix_x[7:5] over that range walks 7,0,1,2,3 — we use the bottom 3 bits
    //   and only enable inside the [480,640) window, so the "7" cell is masked.
    wire [2:0] score_col = pix_x[7:5];
    wire score_bar = is_header && (row_local >= 5'd10) && (row_local < 5'd20)
                     && (pix_x >= 10'd512) && (score_col < score);

    // =====================================================================
    // Game-over / win overlay (flat band — no border, no checker)
    // =====================================================================
    wire overlay_zone = (pix_x[9:6] >= 4'd3) && (pix_x[9:6] < 4'd7)
                      && (pix_y[9:6] >= 4'd3) && (pix_y[9:6] < 4'd5);
    wire show_overlay = (state == S_OVER || state == S_WIN) && overlay_zone;

    // =====================================================================
    // Color output (2 bits per channel)
    // =====================================================================
    reg [1:0] r, g, b;

    always @(*) begin
        r = 2'd0; g = 2'd0; b = 2'd0;

        if (!display_on) begin
            // blanking
        end

        // --- Overlays (highest priority) ---
        else if (show_overlay) begin
            r = 2'b11;
            g = (state == S_WIN) ? 2'b11 : 2'b00;
            b = 2'b00;
        end

        // --- Frog sprite ---
        else if (show_frog) begin
            if (feye_l | feye_r)
                begin r = 2'b11; g = 2'b11; b = 2'b11; end // white eye
            else
                begin r = 2'b00; g = 2'b11; b = 2'b00; end // body green
        end

        // --- Road lanes ---
        else if (is_road) begin
            if (pix_has_obj) begin
                // Car colors per lane
                case (top_row)
                    4'd7:  begin r = 2'b11; g = 2'b00; b = 2'b00; end // red
                    4'd8:  begin r = 2'b11; g = 2'b11; b = 2'b00; end // yellow
                    4'd9:  begin r = 2'b10; g = 2'b00; b = 2'b11; end // purple
                    default: begin r = 2'b11; g = 2'b11; b = 2'b11; end
                endcase
            end else if (road_stripe) begin
                r = 2'b11; g = 2'b11; b = 2'b00; // dashed yellow line
            end else begin
                r = 2'b01; g = 2'b01; b = 2'b01; // dark gray
            end
        end

        // --- River lanes ---
        else if (is_river) begin
            if (pix_has_obj) begin
                r = 2'b10; g = 2'b01; b = 2'b00; // log brown
            end else begin
                r = 2'b00;
                g = sparkle ? 2'b01 : 2'b00;
                b = sparkle ? 2'b11 : 2'b10;
            end
        end

        // --- Goal zone ---
        else if (is_goal) begin
            if (in_pad) begin
                if (gz_filled)
                    begin r = 2'b11; g = 2'b11; b = 2'b00; end // filled = bright yellow
                else
                    begin r = 2'b00; g = 2'b10; b = 2'b01; end // open = teal pad
            end else begin
                r = 2'b00; g = 2'b00; b = 2'b10; // water behind
            end
        end

        // --- Header ---
        else if (is_header) begin
            if (show_life)
                begin r = 2'b00; g = 2'b11; b = 2'b00; end
            else if (score_bar)
                begin r = 2'b11; g = 2'b11; b = 2'b11; end
            else
                begin r = 2'b00; g = 2'b00; b = 2'b01; end // dark blue
        end

        // --- Median / grass ---
        else if (is_median || is_grass) begin
            r = 2'b00;
            g = (pix_x[2] ^ pix_y[2]) ? 2'b11 : 2'b10; // checkerboard grass
            b = 2'b00;
        end
    end

    // =====================================================================
    // VGA output mapping (Tiny VGA Pmod)
    // =====================================================================
    assign uo_out[0] = display_on ? r[1] : 1'b0;   // R1
    assign uo_out[1] = display_on ? g[1] : 1'b0;   // G1
    assign uo_out[2] = display_on ? b[1] : 1'b0;   // B1
    assign uo_out[3] = vsync;
    assign uo_out[4] = display_on ? r[0] : 1'b0;   // R0
    assign uo_out[5] = display_on ? g[0] : 1'b0;   // G0
    assign uo_out[6] = display_on ? b[0] : 1'b0;   // B0
    assign uo_out[7] = hsync;

    // =====================================================================
    // Audio: frame-timed SFX — hop blip, death buzz, goal jingle
    // 20-bit DDS accumulator: f ≈ 25 MHz × freq / 2^20
    //   freq 11 → ~262 Hz (C4)   freq 14 → ~334 Hz (E4)
    //   freq 17 → ~405 Hz (G4)   freq 18 → ~429 Hz (A4)
    // =====================================================================
    reg         audio_out;
    reg  [15:0] snd_acc;
    reg  [6:0]  snd_frames;
    reg  [1:0]  snd_type;      // 0=none, 1=hop, 2=death, 3=goal

    // Goal jingle sliced by snd_frames[5:4]: each segment ~16 frames.
    // snd_frames starts at 64 and counts down → bits 5:4 walk 3,2,1,0
    // giving notes C4 → (gap) → E4 → G4.
    reg [4:0] goal_freq;
    always @(*) begin
        case (snd_frames[5:4])
            2'd3: goal_freq = 5'd11;  // C4
            2'd2: goal_freq = 5'd0;   // gap
            2'd1: goal_freq = 5'd14;  // E4
            default: goal_freq = 5'd17; // G4 held
        endcase
    end

    reg [4:0] cur_freq;
    always @(*) begin
        case (snd_type)
            2'd1:    cur_freq = 5'd18;                              // hop A4
            2'd2:    cur_freq = snd_frames[2] ? 5'd5 : 5'd7;        // death warble
            2'd3:    cur_freq = goal_freq;
            default: cur_freq = 5'd0;
        endcase
    end

    always @(posedge clk) begin
        if (~rst_n) begin
            audio_out  <= 1'b0;
            snd_acc    <= 16'd0;
            snd_frames <= 7'd0;
            snd_type   <= 2'd0;
        end else begin
            if (snd_die) begin
                snd_frames <= 7'd45;
                snd_type   <= 2'd2;
            end else if (snd_goal) begin
                snd_frames <= 7'd63;   // 4 segments × 16 frames
                snd_type   <= 2'd3;
            end else if (snd_hop) begin
                snd_frames <= 7'd5;
                snd_type   <= 2'd1;
            end

            if (frame_tick) begin
                if (snd_frames != 7'd0)
                    snd_frames <= snd_frames - 7'd1;
                else
                    snd_type <= 2'd0;
            end

            if (cur_freq != 5'd0) begin
                snd_acc   <= snd_acc + {11'd0, cur_freq};
                audio_out <= snd_acc[15];
            end else begin
                audio_out <= 1'b0;
                snd_acc   <= 16'd0;
            end
        end
    end

endmodule
