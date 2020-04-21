module as4c4m16sa #(
	// The minimum possible clock rate is 64.103 kHz, at which point the controller is saturated by auto refresh commands
    parameter CLK_RATE = 143000000,
	parameter SPEED_GRADE = 7, // 7, 6, or 5
	parameter READ_BURST_LENGTH = 1, // 1, 2, 4, 8, or 256 (full page)
	parameter WRITE_BURST = 1, // 0 = Single write mode, 1 = Burst write mode (same length as read burst)
	parameter CAS_LATENCY = 2 // 2 or 3
) (
	// Also connect this to the SDRAM chip
	input logic clk,

	// 0 = Idle
	// 1 = Write (with Auto Precharge)
	// 2 = Read (with Auto Precharge)
	// 3 = Self Refresh (TODO)
	input logic [1:0] command,
	input logic [21:0] data_address,
	input logic [15:0] data_write,
	output logic [15:0] data_read,
	output logic data_ready = 1'b0, // goes high when a burst-read is ready
	output logic data_next = 1'b0, // goes high once the first write of a burst-write / single-write is done

	// These ports should be connected directly to the SDRAM chip
	output logic cke = 1'b0,
	output logic [1:0] ba,
	output logic [11:0] a,
	output logic cs = 1'b0,
	output logic ras = 1'b1,
	output logic cas = 1'b1,
	output logic we = 1'b1,
	output logic [1:0] dqm = 2'b11,
	inout wire [15:0] dq
);

localparam READ_BURST_BITS = READ_BURST_LENGTH == 1 ? 3'd0 : READ_BURST_LENGTH == 2 ? 3'd1 : READ_BURST_LENGTH == 4 ? 3'd2 : READ_BURST_LENGTH == 8 ? 3'd3 : READ_BURST_LENGTH == 256 ? 3'd7 : 3'd0;

localparam ROW_CYCLE_TIME = 								(SPEED_GRADE == 5 ? 55 : SPEED_GRADE == 6 ? 60 : 63) / 1.0E9 * $unsigned(CLK_RATE);
localparam RAS_TO_CAS_DELAY = 								(SPEED_GRADE == 5 ? 15 : SPEED_GRADE == 6 ? 18 : 21) / 1.0E9 * $unsigned(CLK_RATE);
localparam PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK = RAS_TO_CAS_DELAY;
localparam ROW_ACTIVATE_TO_ROW_ACTIVATE_DIFFERENT_BANK = 	(SPEED_GRADE == 5 ? 10 : SPEED_GRADE == 6 ? 12 : 14) / 1.0E9 * $unsigned(CLK_RATE);
localparam ROW_ACTIVATE_TO_PRECHARGE_SAME_BANK = 			(SPEED_GRADE == 5 ? 40 : SPEED_GRADE == 6 ? 42 : 42) / 1.0E9 * $unsigned(CLK_RATE);

localparam MODE_REGISTER_SET_CYCLE_TIME = 2;
localparam WRITE_RECOVERY_TIME = MODE_REGISTER_SET_CYCLE_TIME;

localparam AVERAGE_REFRESH_INTERVAL_TIME = 15.6 / 1.0E6 * $unsigned(CLK_RATE);


// 0 = Uninit (mode register set required)
// 1 = Idle
// 2 = Writing
// 3 = Reading
// 4 = Waiting (countdown) could be any of the delays, including a refresh
logic [2:0] state = 3'd0;

localparam REFRESH_TIMER_WIDTH = $clog2(int'(AVERAGE_REFRESH_INTERVAL_TIME + 1));
localparam REFRESH_TIMER_END = REFRESH_TIMER_WIDTH'(AVERAGE_REFRESH_INTERVAL_TIME);
logic [REFRESH_TIMER_WIDTH-1:0] refresh_timer = REFRESH_TIMER_WIDTH'(0);

always @(posedge clk)
begin
	// TODO: abort a read/write and refresh if it's taking too long (i.e. full-page)
	if (state == 3'd1 && refresh_timer >= REFRESH_TIMER_END) // Refresh will always occur from an idle state
		refresh_timer <= REFRESH_TIMER_WIDTH'(0);
	else if (state == 3'd0) // Don't run timer when uninitialized
		refresh_timer <= REFRESH_TIMER_WIDTH'(0);
	else
		refresh_timer <= refresh_timer + 1'd1;
end

localparam COUNTER_WIDTH = $clog2(int'(ROW_CYCLE_TIME + 1));
logic [COUNTER_WIDTH-1:0] countdown = COUNTER_WIDTH'(0);

// Jump from waiting to a specified state
logic [2:0] destination_state = 3'd0;

// "Step" counter used for burst write/read counting and initialization steps. Must be at least 3 bits wide.
localparam STEP_WIDTH = $clog2(READ_BURST_LENGTH == 1 ? 8 : READ_BURST_LENGTH + 1 + CAS_LATENCY);
logic [STEP_WIDTH-1:0] step = STEP_WIDTH'(0);

logic [15:0] internal_dq = 16'd0;
assign dq = state == 3'd2 ? internal_dq : 16'hzzzz; // Tri-State driver

always @(posedge clk)
begin
	cs <= 1'b0;
	if (state == 3'd0) // Uninit
	begin
		step <= step + 1'd1;
		$display("Initializing %d", step);

		// See Note 11 on page 20: Power up Sequence
		if (step == 3'd0) // Enable clock
		begin
			cke <= 1'b1;
			ras <= 1'b1; // No-Operation
			cas <= 1'b1;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end
		else if (step == 3'd1) // Pre-charge all banks
		begin
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK));
			destination_state <= 3'd0;
			ras <= 1'b0;
			cas <= 1'b1;
			we <= 1'b0;
			ba <= 2'dx;
			a <= {1'bx, 1'b1, 10'dx};
		end
		else if (step == 3'd2 || step == 3'd3) // Double auto refresh
		begin
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(ROW_CYCLE_TIME));
			destination_state <= 3'd0;
			ras <= 1'b0;
			cas <= 1'b0;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end
		else if (step == 3'd4) // Mode register set
		begin
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(MODE_REGISTER_SET_CYCLE_TIME));
			destination_state <= 3'd0;
			ras <= 1'b0;
			cas <= 1'b0;
			we <= 1'b0;
			ba <= 2'b00;
			a <= {2'b00, WRITE_BURST == 1 ? 1'b1 : 1'b0, 2'b00, CAS_LATENCY == 2 ? 3'b010 : 3'b011, 1'b0,  READ_BURST_BITS};
		end
		else if (step == 3'd5) // Extended mode register set
		begin
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(MODE_REGISTER_SET_CYCLE_TIME));
			destination_state <= 3'd1;
			ras <= 1'b0;
			cas <= 1'b0;
			we <= 1'b0;
			ba <= 2'b01;
			a <= {10'd0, 1'b1, 1'b0}; // Weak driver
		end
	end
	else if (state == 3'd1) // Idle
	begin
		if (refresh_timer >= REFRESH_TIMER_END) // Refresh timer expires
		begin
			$display("Refreshing");
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(ROW_CYCLE_TIME));
			destination_state <= 3'd1;
			ras <= 1'b0;
			cas <= 1'b0;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end
		else if (command == 2'd1 || command == 2'd2) // Write or Read (does a bank activate)
		begin
			$display("Enter R/W");
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(RAS_TO_CAS_DELAY));
			destination_state <= command == 2'd1 ? 3'd2 : 3'd3; // go to the correct state
			ras <= 1'b0;
			cas <= 1'b1;
			we <= 1'b1;
			ba <= data_address[21:20];
			a <= data_address[19:8];
			dqm <= {command == 2'd1, command == 2'd1}; // Make dq inputs for writing, or outputs for reading
			step <= STEP_WIDTH'(0);
		end
		else
		begin
			state <= 3'd1;
			ras <= 1'b1; // No-Operation
			cas <= 1'b1;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end
	end
	else if (state == 3'd2) // Writing
	begin
		$display("Writing %d", step);
		internal_dq <= data_write;
		dqm <= 2'b11;
		step <= step + 1'd1;
		if (step == STEP_WIDTH'(0)) // Write with Auto Precharge
		begin
			ras <= 1'b1;
			cas <= 1'b0;
			we <= 1'b0;
			ba <= data_address[21:20];
			a <= {1'bx, 1'b1, 2'bxx, data_address[7:0]};
		end
		else // No-Operation
		begin
			ras <= 1'b1;
			cas <= 1'b1;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end

		if (step == STEP_WIDTH'(WRITE_BURST ? $unsigned(READ_BURST_LENGTH) : 1)) // Last write just finished
		begin
			$display("Done!");
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(WRITE_RECOVERY_TIME) - 1 + $unsigned(PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK));
			destination_state <= 3'd1;
			data_next <= 1'b0;
		end // Still writing
		else
			data_next <= 1'b1;
	end
	else if (state == 3'd3) // Reading
	begin
		$display("Reading %d", step);
		internal_dq <= ~16'd0; // Set tri-state driver to high
		dqm <= 2'b00;
		step <= step + 1'd1;
		if (step == STEP_WIDTH'(0)) // Read with Auto Precharge
		begin
			ras <= 1'b1;
			cas <= 1'b0;
			we <= 1'b1;
			ba <= data_address[21:20];
			a <= {1'bx, 1'b1, 2'bxx, data_address[7:0]};
		end
		else // No-Operation
		begin
			ras <= 1'b1;
			cas <= 1'b1;
			we <= 1'b1;
			ba <= 2'dx;
			a <= 12'dx;
		end
		
		if (step == STEP_WIDTH'($unsigned(CAS_LATENCY) + $unsigned(READ_BURST_LENGTH))) // Last read just finished
		begin
			$display("Read done");
			state <= 3'd4;
			countdown <= COUNTER_WIDTH'($unsigned(CAS_LATENCY) + $unsigned(PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK));
			destination_state <= 3'd1;
			data_ready <= 1'b0;
		end
		else if (step >= STEP_WIDTH'($unsigned(CAS_LATENCY))) // Still reading
		begin
			data_read <= dq;
			data_ready <= 1'b1;
		end
	end
	else if (state == 3'd4) // Waiting
	begin
		$display("Waiting %d", countdown);
		if (countdown == COUNTER_WIDTH'(0))
			state <= destination_state;
		else
			countdown <= countdown - 1'd1;
		ras <= 1'b1; // No-Operation
		cas <= 1'b1;
		we <= 1'b1;
		ba <= 2'dx;
		a <= 12'dx;
	end
end

endmodule
