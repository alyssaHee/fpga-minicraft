// Takes in location of player and returns block type of a block within 1 block to the upper left of the player
// Blocks to left of player take priority, blocks above player take second priority
module object_map_READ (Resetn, Clock, go, map, locationX, locationY, blockExists, blockTypeIn, blockTypeOut, addr, xBlock, yBlock);
	input Resetn, Clock, go;
	input wire [1199:0] map;
	input [9:0] locationX;			// ASSUMING THE LOCATIONS ARE PASSED IN REGULAR FORM (0-640, 0-480)
	input [8:0] locationY;
	input [2:0] blockTypeIn;		// Kept blockTypeIn and blockTypeOut to allow us to know which kind of block is at a certain location
									// blockTypeIn will be passed in, if that type of block is there, the blockType will be output back. Otherwise, it will output 0000
							// ****From here, we can XOR the blockTypeOut from all the objects to find the blockType that is at the location!!
			
	output reg [2:0] blockTypeOut;	// 3'b000 means no block at the location (000 will be used as the background block)
	output reg blockExists;
	output reg [10:0] addr;
	output reg [9:0] xBlock;		// Outputs the x position and y position to draw blocks at
	output reg [8:0] yBlock;		// These are in form that the draw module can take (0-640, 0-480)
	
	// turn the location closest to upper left corner of player into its closest grid location
	wire [6:0] xGridLocation = locationX/16;
	wire [5:0] yGridLocation = locationY/16;
	
	reg [6:0] distanceL, distanceT;
	reg done;
	
	always @(posedge Clock)
	begin
        if (!Resetn)
		begin
			blockExists <= 1'b0;
			blockTypeOut <= 3'b000;
			addr <= 0;
			done <= 1'b0;
			distanceL <= 0;
			distanceT <= 0;
			xBlock <= 10'b0;
			yBlock <= 9'b0;
		end
		else if (go)
		begin
			if (xGridLocation == 0 & yGridLocation == 0) // If the player is at the upper left corner, no blocks
			begin
				done <= 1'b1;
				addr <= 11'b11111111111; 				// Set the address to big number that is not in the map
			end
			else if (xGridLocation == 0)				// If the player is at leftmost edge of map
			begin										// We can only check if there is a block above player
				addr <= 40*((yGridLocation - 1));
				if (map[40*((yGridLocation - 1))] == 1'b1)
				begin
					blockTypeOut <= blockTypeIn;
					blockExists <= 1'b1;
				end
				else
				begin
					blockTypeOut <= 3'b000;
					blockExists <= 1'b0;
				end
				xBlock <= xGridLocation*16;
				yBlock <= (yGridLocation-1)*16;
				done <= 1'b1;
			end
			else if (yGridLocation == 0)				// If the player is at the topmost edge of map
			begin										// We can only check if there is a block to left of player
				addr <= (xGridLocation - 1);
				if (map[(xGridLocation - 1)] == 1'b1)
				begin
					blockTypeOut <= blockTypeIn;
					blockExists <= 1'b1;
				end
				else
				begin
					blockTypeOut <= 3'b000;
					blockExists <= 1'b0;
				end
				xBlock <= (xGridLocation-1)*16;
				yBlock <= yGridLocation*16;
				done <= 1'b1;
			end
			else 										// Most general case, two possible locations for blocks to be
			begin										// Want to select block closest to player of the two				
				// check which location is closer to player
				distanceL <= locationX%16;
				distanceT <= locationY%16;
				if (distanceL <= distanceT)
				begin
					addr <= 40*(yGridLocation) + (xGridLocation - 1);
					if (map[40*(yGridLocation) + (xGridLocation - 1)] == 1'b1)
					begin
						blockTypeOut <= blockTypeIn;
						blockExists <= 1'b1;
					end
					else
					begin
						blockTypeOut <= 3'b000;
						blockExists <= 1'b0;
					end
					xBlock <= (xGridLocation-1)*16;
					yBlock <= yGridLocation*16;
					done <= 1'b1;
				end
				else
				begin
					addr <= 40*((yGridLocation-1)) + (xGridLocation);
					if (map[40*((yGridLocation-1)) + (xGridLocation)] == 1'b1)
					begin
						blockTypeOut <= blockTypeIn;
						blockExists <= 1'b1;
					end
					else
					begin
						blockTypeOut <= 3'b000;
						blockExists <= 1'b0;
					end
					xBlock <= xGridLocation*16;
					yBlock <= (yGridLocation-1)*16;
					done <= 1'b1;
				end
			end
		end
    end
endmodule
