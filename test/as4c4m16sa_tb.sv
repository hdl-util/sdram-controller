module as4c4m16sa_tb ();

logic SDRAM_CLK = 1'b0;

always #2 SDRAM_CLK <= ~SDRAM_CLK;

logic [1:0] command = 2'd0;
logic [21:0] data_address = 22'd0;
logic [15:0] data_write = 16'd0;
logic [15:0] data_read;
logic data_read_valid;
logic data_write_done;

logic [11:0] address;
logic [1:0] ba;
logic cas;
logic cke;
logic cs;
wire [15:0] dq;
logic [1:0] dqm;
logic ras;
logic we;

logic [15:0] dq_in = 16'dx;
logic inoutmode = 1'b0;
assign dq = inoutmode ? dq_in : 16'dz;

as4c4m16sa_controller #(.CAS_LATENCY(2)) as4c4m16sa ( // have to fake the CAS latency here so the tests can be simpler
	.clk(SDRAM_CLK),
    .command(command),
    .data_address(data_address),
    .data_write(data_write),
    .data_read(data_read),
    .data_read_valid(data_read_valid),
    .data_write_done(data_write_done),
    .clock_enable(cke),
    .bank_activate(ba),
    .address(address),
    .chip_select(cs),
    .row_address_strobe(ras),
    .column_address_strobe(cas),
    .write_enable(we),
    .dqm(dqm),
    .dq(dq)
);

logic [15:0] dram [0:3] [0:4095] [0:255];
logic [11:0] mode_register;
logic [11:0] extended_mode_register;
logic last_cke = 1'b0;

logic [1:0] active_bank = 2'dx;
logic [11:0] row_address = 12'dx;
logic [7:0] column_address = 8'dx;

logic [8:0] read_countdown = 9'd0;
logic [8:0] write_countdown = 9'd0;

logic [8:0] burst_size;
assign burst_size = mode_register[2:0] == 0 ? 1 : mode_register[2:0] == 1 ? 2 : mode_register[2:0] == 2 ? 4 : mode_register[2:0] == 3 ? 8 : mode_register == 7 ? 256 : 0;

always @(posedge SDRAM_CLK)
begin
    last_cke <= cke;
    if (!last_cke && cke)
    begin
        // $display("Clock enabled");
    end
    if (last_cke)
    begin
        if (!ras && cas && !we && address[10])
        begin
            // $display("PrechargeAll");
        end
        else if (!ras && cas && !we && !address[10])
        begin
            // $display("BankPrecharge");
        end
        else if (!ras && !cas && !we)
        begin
            if (ba[0])
            begin
                // $display("Extended Mode Register Set: %b", address);
                extended_mode_register <= address;
            end
            else
            begin
                // $display("Mode Register Set: %b", address);
                mode_register <= address;
            end
        end
        else if (!ras && !cas && we)
        begin
            // $display("AutoRefresh");
        end
        else if (!ras && cas && we)
        begin
            // $display("BankActivate: %d @ 0x%h", ba, address);
            active_bank <= ba;
            row_address <= address;
        end
        else if (ras && !cas && !we)
        begin
            column_address = address[7:0];
            write_countdown = mode_register[9] ? 1 : burst_size;
        end
        else if (ras && !cas && we)
        begin
            column_address <= address[7:0];
            read_countdown <= burst_size;
        end

        assert (~(write_countdown != 9'd0) || ~(read_countdown != 9'd0)) else $fatal(1, "I/O conflict, cancelled reads/writes not implemented");
        if (write_countdown != 9'd0)
        begin
            // $display("Write: %h @ 0x%h%h%h", dq, active_bank, row_address, column_address);
            dram[active_bank][row_address][column_address] <= dq;
            write_countdown = write_countdown - 1'd1;
            inoutmode <= 1'b0;
        end
        else if (read_countdown != 9'd0)
        begin
            // $display("Read: %h @ 0x%h%h%h", dram[active_bank][row_address][column_address], active_bank, row_address, column_address);
            dq_in <= dram[active_bank][row_address][column_address];
            read_countdown = read_countdown - 1'd1;
            inoutmode <= 1'b1;
        end
        else
            inoutmode <= 1'b0;
    end
end

logic write_done = 1'd0;
logic read_done = 1'd0;
logic [21:0] counter = 22'd0;

always @(posedge SDRAM_CLK)
begin
    if (command == 2'd0 && !write_done)
    begin
        command <= 2'd1;
    end
    else if (command == 2'd1 && data_write_done)
    begin
        command <= 2'd0;
        data_address <= data_address + 1'd1 == 22'h0_100_00 ? 22'd0 : data_address + 1'd1;
        data_write <= data_write + 1'd1;
        if (data_address + 1'd1 == 22'h0_100_00)
            write_done <= 1'd1;
    end
    else if (command == 2'd0 && write_done)
    begin
        command <= 2'd2;
    end
    else if (command == 2'd2 && data_read_valid)
    begin
        command <= 2'd0;
        data_address <= data_address + 1'd1 == 22'h0_100_00 ? 22'd0 : data_address + 1'd1;
        data_write <= data_write + 1'd1;
        assert (data_address[15:0] == data_read) else $fatal(1, "Not equal for %h @ 0x%h", data_read, data_address);
        if (data_address + 1'd1 == 22'h0_100_00)
            $finish;
    end
end

initial
begin
    assert (as4c4m16sa.sdram_controller.ROW_CYCLE_CLOCKS == 9) else $fatal(1, "%d", as4c4m16sa.sdram_controller.ROW_CYCLE_CLOCKS);
    assert (as4c4m16sa.sdram_controller.RAS_TO_CAS_DELAY_CLOCKS == 3) else $fatal(1, "");
    assert (as4c4m16sa.sdram_controller.PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK_CLOCKS == 3) else $fatal(1, "");
    assert (as4c4m16sa.sdram_controller.ROW_ACTIVATE_TO_ROW_ACTIVATE_DIFFERENT_BANK_CLOCKS == 2) else $fatal(1, "");
    assert (as4c4m16sa.sdram_controller.ROW_ACTIVATE_TO_PRECHARGE_SAME_BANK_CLOCKS == 6) else $fatal(1, "");
    assert (as4c4m16sa.sdram_controller.AVERAGE_REFRESH_INTERVAL_CLOCKS == 2231) else $fatal(1, "%d", as4c4m16sa.sdram_controller.AVERAGE_REFRESH_INTERVAL_CLOCKS);
    assert (as4c4m16sa.sdram_controller.REFRESH_TIMER_WIDTH == 12) else $fatal(1, "%d", as4c4m16sa.sdram_controller.REFRESH_TIMER_WIDTH);
    assert (as4c4m16sa.sdram_controller.COUNTER_WIDTH == 15) else $fatal(1, "%d", as4c4m16sa.sdram_controller.COUNTER_WIDTH);
    assert (as4c4m16sa.sdram_controller.STEP_WIDTH == 3) else $fatal(1, "%d", as4c4m16sa.sdram_controller.STEP_WIDTH);
end

endmodule
