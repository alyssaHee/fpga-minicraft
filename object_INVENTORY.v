/* This code creates the inventory of the player.
*  
*  The inventoryCounter just increments or decrements the number of certain object blocks the player has.
*   - for 6 different object blocks we will need 6 different instantiations of this module
*   - make sure to set the BLOCKTYPE parameter of each block so that they can be differentiated
*
*  The invHexDisplay displays the number of objects the player has.
*   - each HEX display is mapped to a different object block
*
*  To use:
*   1. Create 6 different inventoryCounter instantiations and set the appropriate BLOCKTYPE parameter
*   2. Instantiate invHexDisplay once and pass blockType to it after each inventory update
*     - maybe set go of invHexDisplay to 1 everytime an inventory is updated so that the hex can update?
*/


// Increments/decrements the inventory by one
module inventoryCounter (Resetn, clock, go, add, subtract, blockType, number, canPlace, canBreak);
	parameter BLOCKTYPE = 3'b001;		// Define blocktype of each block here so we can increment correct inventory
	
	input Resetn, clock, go, add, subtract;
	input [2:0] blockType;
	output reg [3:0] number;			// the number of blocks in inventory
	output reg canPlace, canBreak;		// to be output for drawing module and writing module to know if blocks can be placed or broken
	initial
		begin
			number <= 4'b0000;
			canBreak <= 1'b1;	// At the start the player is able to break blocks
			canPlace <= 1'b0;	// but cannot place because no blocks in inventory
			done <= 1'b0;
		end

	reg done;	// this allows us to only add once at a time

	always@(posedge clock)
	begin
		
		if (!go)
		begin
			done <= 1'b0;
			canBreak <= (number == 15 || blockType != BLOCKTYPE) ? 1'b0 : 1'b1;
			canPlace <= (number == 0 || blockType != 3'b000)  ? 1'b0 : 1'b1;
		end
		else if (go && blockType == BLOCKTYPE && !done)
		begin
			if (add && number < 15 && canBreak == 1)	// keep the number at 15 (max)
			begin
				number <= number + 4'b0001;
				done <= 1'b1;
			end
			else if (subtract && number > 0 && canPlace == 1) // only subtract (place block) if inventory has blocks
			begin
				number <= number - 4'b0001;
				done <= 1'b1;
			end
		end	
	end
endmodule

// Pass the number of blocks from inventory counter and the blockType to display on correct HEX display
module invHexDisplay (Resetn, clock, go, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, blockType, number);
	input Resetn, clock, go;
	input [3:0] number;
	input [2:0] blockType;
	output reg [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;

	wire [6:0] hex;

	assign hex = (number == 4'b0000) ? 7'b0111111:	// 0
		(number == 4'b0001) ? 7'b0000110:		// 1
		(number == 4'b0010) ? 7'b1011011:		// 2
		(number == 4'b0011) ? 7'b1001111:		// 3
		(number == 4'b0100) ? 7'b1100110:		// 4
		(number == 4'b0101) ? 7'b1101101:		// 5
		(number == 4'b0110) ? 7'b1111101:		// 6
		(number == 4'b0111) ? 7'b0000111:		// 7
		(number == 4'b1000) ? 7'b1111111:		// 8	
		(number == 4'b1001) ? 7'b1100111:		// 9	
		(number == 4'b1010) ? 7'b1110111:		// A - 10
		(number == 4'b1011) ? 7'b1111100:		// b - 11	
		(number == 4'b1100) ? 7'b0111001:		// C - 12
		(number == 4'b1101) ? 7'b1011110:		// d - 13
		(number == 4'b1110) ? 7'b1111001:		// E - 14
		(number == 4'b1111) ? 7'b1110001:		// F - 15
			7'b0000000;
	
	always@(posedge clock)
	begin
		if (Resetn)	// Set all displays to 0
		begin
			HEX5 <= 7'b1000000;
			HEX4 <= 7'b1000000;
			HEX3 <= 7'b1000000;
			HEX2 <= 7'b1000000;
			HEX1 <= 7'b1000000;
			HEX0 <= 7'b1000000;
		end
		else if (go)
		begin
			if (blockType == 3'b001)		// Update the hex display with number if blockType is correct
				HEX5 <= ~hex;
			else if (blockType == 3'b010)
				HEX4 <= ~hex;
			else if (blockType == 3'b011)
				HEX3 <= ~hex;
			else if (blockType == 3'b100)
				HEX2 <= ~hex;
			else if (blockType == 3'b101)
				HEX1 <= ~hex;
			else if (blockType == 3'b110)
				HEX0 <= ~hex;
		end
	end
endmodule
