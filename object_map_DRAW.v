// outputs an x and y location if there is a block located in the position (to be sent to draw block module)
module object_map_DRAW (Resetn, Clock, go, done, map, data_out, xLocation, yLocation);
	input Resetn, Clock, go;
	input wire [1199:0] map;
	
	output reg data_out;  		// data from the reg
	reg [10:0] addr;    // address counter to track which cell is being read
	output reg done;
	
	output reg [9:0] xLocation;
	output reg [8:0] yLocation;

	always @(posedge Clock)
	begin
        if (!Resetn)
		begin
			addr      <= 11'b0;
			done      <= 1'b0;
			data_out  <= 1'b0;
			xLocation <= 10'b0;
			yLocation <= 9'b0;
		end
		else if (go && !done && !data_out)
		begin
			data_out <= map[addr];
			if (map[addr] == 1'b1)
			begin
				xLocation <= (addr % 40)*16;
				yLocation <= (addr / 40)*16;
			end
			// advance address
			if (addr == 11'd1199)
				done <= 1'b1;
			else
				addr <= addr + 1;
			// else hold last x/y
		end
		else if (!go)
			data_out <= 1'b0;
    end
endmodule
