module vv35_zynq7020_clk200 (
    input  wire clk50_i,
    input  wire rst_i,
    output wire clk200_o,
    output wire locked_o
);
    wire clkfb_raw;
    wire clkfb_buf;
    wire clk200_raw;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(20.000),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(20.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .STARTUP_WAIT("FALSE")
    ) i_mmcm (
        .CLKIN1(clk50_i),
        .RST(rst_i),
        .PWRDWN(1'b0),
        .CLKFBIN(clkfb_buf),
        .CLKFBOUT(clkfb_raw),
        .CLKFBOUTB(),
        .CLKOUT0(clk200_raw),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked_o)
    );

    BUFG i_clkfb_buf (.I(clkfb_raw), .O(clkfb_buf));
    BUFG i_clk200_buf (.I(clk200_raw), .O(clk200_o));
endmodule
