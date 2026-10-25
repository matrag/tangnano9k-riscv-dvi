// Clock generation for 640x480@60 DVI/HDMI
//
//   clk_27  --> rPLL --> clk_tmds  126.0 MHz  (5x pixel clock, for the 10:1 DDR serializer)
//                    \-> CLKDIV /5 --> clk_pix  25.2 MHz  (pixel clock)
//
// rPLL math (GW1NR-9C):
//   CLKOUT = FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1)  = 27 * 14 / 3  = 126 MHz
//   PFD    = FCLKIN / (IDIV_SEL+1)                  = 9 MHz     (must be >= 3 MHz)
//   VCO    = CLKOUT * ODIV_SEL                      = 1008 MHz  (must be 400..1200 MHz)

module clocks (
    input  wire clk_27,
    output wire clk_tmds,   // 126 MHz
    output wire clk_pix,    // 25.2 MHz
    output wire lock        // high once the PLL output is stable
);

    rPLL #(
        .FCLKIN("27"),
        .DEVICE("GW1NR-9C"),
        .DYN_IDIV_SEL("false"),
        .IDIV_SEL(2),
        .DYN_FBDIV_SEL("false"),
        .FBDIV_SEL(13),
        .DYN_ODIV_SEL("false"),
        .ODIV_SEL(8),
        .PSDA_SEL("0000"),
        .DYN_DA_EN("true"),
        .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1),
        .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),
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
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );

    // Dedicated clock divider; its output phase-aligns with clk_tmds,
    // which the OSER10 serializer will need in step 2.
    CLKDIV #(
        .DIV_MODE("5")
    ) div5 (
        .HCLKIN(clk_tmds),
        .RESETN(1'b1),
        .CALIB(1'b0),
        .CLKOUT(clk_pix)
    );

endmodule
