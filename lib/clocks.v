// Clock generation for 640x480@60 DVI/HDMI
//
//   clk_27  --> rPLL --> clk_tmds  126.0 MHz  (5x pixel clock, for the 10:1 DDR serializer)
//                    \-> CLKDIV /5 --> clk_pix  25.2 MHz  (pixel clock)
//
// Why these two frequencies?
//   - 640x480@60 needs 800 x 525 x 60 = 25.2 million pixel clocks per second
//     (the frame is bigger than 640x480 because of blanking, see video_timing.v).
//   - Every pixel, each TMDS lane sends a 10-bit word: 10 x 25.2 = 252 Mbit/s.
//   - The OSER10 serializer outputs on BOTH clock edges (DDR), so it needs
//     252 / 2 = 126 MHz, i.e. exactly 5x the pixel clock.
//
// rPLL math (GW1NR-9C):
//   CLKOUT = FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1)  = 27 * 14 / 3  = 126 MHz
//   PFD    = FCLKIN / (IDIV_SEL+1)                  = 9 MHz     (must be >= 3 MHz)
//   VCO    = CLKOUT * ODIV_SEL                      = 1008 MHz  (must be 400..1200 MHz)
//
//   The PFD (phase/frequency detector) compares the divided input with the
//   divided feedback. The VCO (voltage controlled oscillator) is the PLL's
//   internal oscillator; it runs fast and ODIV_SEL divides it back down to
//   CLKOUT. Choosing ODIV_SEL so the VCO lands inside its legal range is part
//   of picking the settings (Gowin's IP generator does the same search).

module clocks (
    input  wire clk_27,
    output wire clk_tmds,   // 126 MHz
    output wire clk_pix,    // 25.2 MHz
    output wire lock        // high once the PLL output is stable
);

    // Parameter list as produced by Gowin's IP generator. Only FCLKIN,
    // IDIV_SEL, FBDIV_SEL and ODIV_SEL matter here; the rest disable the
    // dynamic (runtime-adjustable) features, phase shift and duty-cycle tuning.
    rPLL #(
        .FCLKIN("27"),                // input frequency in MHz, as a string
        .DEVICE("GW1NR-9C"),
        .DYN_IDIV_SEL("false"),       // false = use the fixed IDIV_SEL below, not the IDSEL port
        .IDIV_SEL(2),                 // input divider:    27 / 3  = 9 MHz
        .DYN_FBDIV_SEL("false"),
        .FBDIV_SEL(13),               // feedback divider: 9 * 14  = 126 MHz
        .DYN_ODIV_SEL("false"),
        .ODIV_SEL(8),                 // VCO divider:      126 * 8 = 1008 MHz VCO
        .PSDA_SEL("0000"),            // no phase shift
        .DYN_DA_EN("true"),
        .DUTYDA_SEL("1000"),          // 50% duty cycle
        .CLKOUT_FT_DIR(1'b1),
        .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),       // feedback taken inside the PLL, no external pin
        .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2),
        .CLKOUTD_SRC("CLKOUT"),
        .CLKOUTD3_SRC("CLKOUT")
    ) pll (
        .CLKIN(clk_27),
        .CLKOUT(clk_tmds),
        .LOCK(lock),
        .CLKOUTP(),                   // phase-shifted copy, unused
        .CLKOUTD(),                   // divided output, unused
        .CLKOUTD3(),                  // divided-by-3 output, unused
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),                // dynamic-select ports, ignored because DYN_*="false"
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );

    // Dedicated clock divider; its output phase-aligns with clk_tmds.
    // OSER10 loads a parallel word on the clk_pix edge and shifts it out on
    // clk_tmds, so the two edges must have a fixed relationship. A
    // counter-based /5 in the fabric would add an unknown routing delay;
    // CLKDIV sits on the fast clock network next to the IO logic and
    // guarantees the alignment.
    CLKDIV #(
        .DIV_MODE("5")
    ) div5 (
        .HCLKIN(clk_tmds),
        .RESETN(1'b1),                // never reset the divider
        .CALIB(1'b0),                 // CALIB shifts the output phase; not used
        .CLKOUT(clk_pix)
    );

endmodule
