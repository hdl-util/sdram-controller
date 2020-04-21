module as4c4m16sa_tb ();

logic SDRAM_CLK = 1'b0;

always #2 SDRAM_CLK <= ~SDRAM_CLK;

logic [1:0] command = 2'd0;
logic [21:0] data_address = 22'd0;
logic [15:0] data_write = 16'hFACE;
logic [15:0] data_read;
logic data_read_valid;
logic data_write_done;

logic [11:0] SDRAM_ADDR;
logic [1:0] SDRAM_BA;
logic SDRAM_CASn;
logic SDRAM_CKE;
logic SDRAM_CSn;
wire [15:0] SDRAM_DQ;
logic [1:0] SDRAM_DQM;
logic SDRAM_RASn;
logic SDRAM_WEn;

as4c4m16sa as4c4m16sa (
	.clk(SDRAM_CLK),
    .command(command),
    .data_address(data_address),
    .data_write(data_write),
    .data_read(data_read),
    .data_read_valid(data_read_valid),
    .data_write_done(data_write_done),
    .clock_enable(SDRAM_CKE),
    .bank_activate(SDRAM_BA),
    .address(SDRAM_ADDR),
    .chip_select(SDRAM_CSn),
    .row_address_strobe(SDRAM_RASn),
    .column_address_strobe(SDRAM_CASn),
    .write_enable(SDRAM_WEn),
    .dqm(SDRAM_DQM),
    .dq(SDRAM_DQ)
);

initial
begin
    wait (as4c4m16sa.state == 3'd1);
    command <= 2'd1;
    wait (as4c4m16sa.state == 3'd2);
    wait (data_write_done);
    command <= 2'd0;
    wait (as4c4m16sa.state == 3'd1);
    command <= 2'd2;
    wait (as4c4m16sa.state == 3'd3);
    command <= 2'd0;
    wait (as4c4m16sa.state == 3'd1);
    $finish;
end

endmodule
