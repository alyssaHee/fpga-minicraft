`default_nettype none



/*  This code first displays a background image (MIF) on the VGA output. Then, the code
 *  displays two objects, each of which is read from a small memory, on the screen. Each
 *  object can be moved left/right/up/down by pressing PS2 keyboard keys. To use the circuit,
 *  first use KEY[0] to perform a reset. The background MIF should appear on the VGA output. 
 *  Pressing KEY[1] displays one object, at its initial position, and pressing KEY[2] displays
 *  the other object. Move the first object left/right/up/down using PS2 keys a/s/w/z, and 
 *  the other object using d/f/r/c.
*/

module vga_demo(CLOCK_50, SW, KEY, LEDR, PS2_CLK, PS2_DAT, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);

    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;

    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;

    // state names for the FSM that controls drawing of objects

/*
A: Idle
B: received input
C: Scancode register enabled (we can take inputs yay!)
D: Drawing
*/

    parameter A = 8'b00000000, B = 8'b00000001, C = 8'b00000010, D = 8'b00000011, E = 8'b00000100, F = 8'b00000101, G = 8'b00000110, H = 8'b00000111;
	 parameter I = 8'b00001000, J = 8'b00001001, K = 8'b00001010, L = 8'b00001011, M = 8'b00001100, N = 8'b00001101, O = 8'b00001110, P = 8'b00001111;
	 parameter Q = 8'b00010000, R = 8'b00010001;

	input wire CLOCK_50;
	input wire [9:0] SW;
	input wire [3:0] KEY;
	output wire [9:0] LEDR;
	inout wire PS2_CLK, PS2_DAT;
	output wire [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
	output wire [7:0] VGA_R;
	output wire [7:0] VGA_G;
	output wire [7:0] VGA_B;
	output wire VGA_HS;
	output wire VGA_VS;
	output wire VGA_BLANK_N;
	output wire VGA_SYNC_N;
	output wire VGA_CLK;

    // The signals below are used to multiplex the pixels displayed for the object

	wire [nX-1:0] O1_x, Block_x, MUX_x;    // x coordinate multiplexer
	wire [nY-1:0] O1_y, Block_y, MUX_y;    // y coordinate multiplexer
	wire [8:0] O1_color, Block_color, MUX_color; // color multiplexer
	wire O1_write, Block_write, MUX_write; // write control multiplexer


	wire [1199:0] map1, map2, map3, map4, map5, map6;				// This is for pure reading purposes.

    reg prev_ps2_clk;               // ps2_clk value in the previous clock cycle
    wire negedge_ps2_clk;           // used for PS2 keyboard signals
    wire ps2_rec;                   // set when a PS2 packet has been received
    wire object_sel;                // used to select which object to erase/draw
    reg [32:0] Serial;              // each PS2 serial data packet has 11 bits:
                                    // STOP (1) PARITY d7 d6 d5 d4 d3 d2 d1 d0 START (0)
                                    // 33 total bits are received (scancode/release/scancode
    reg [3:0] Packet;               // used to know when 11 bits have been received
    wire [7:0] scancode;            // used to save the current ps2 scancode
    reg Esc;                        // enable scancode register
    reg step; 					    // move an object

    wire O1_done, Block_done, done; // object move completed
    wire [7:0] O1_dir;              // used to set direction of moving for objects
    reg [7:0] y_Q, Y_D;             // FSM, used to control drawing of objects

    wire Resetn, KEY1, KEY2, KEY3, KEY0;  // Reset, and synchronized versions of KEYs
    wire PS2_CLK_S, PS2_DAT_S;      // synchronized versions of PS2 signals

    assign Resetn = SW[9];
	 sync S0 (~KEY[0], Resetn, CLOCK_50, KEY0);
    sync S1 (~KEY[1], Resetn, CLOCK_50, KEY1);
    sync S2 (~KEY[2], Resetn, CLOCK_50, KEY2);
	sync S5 (~KEY[3], Resetn, CLOCK_50, KEY3);
	
	wire SW1, SW2, SW3, SW4, SW5, SW6;
	debounce deb1 (SW[1], CLOCK_50, SW1);
	debounce deb2 (SW[2], CLOCK_50, SW2);
	debounce deb3 (SW[3], CLOCK_50, SW3);
	debounce deb4 (SW[4], CLOCK_50, SW4);
	debounce deb5 (SW[5], CLOCK_50, SW5);
	debounce deb6 (SW[6], CLOCK_50, SW6);

    sync S3 (PS2_CLK, Resetn, CLOCK_50, PS2_CLK_S);
    sync S4 (PS2_DAT, Resetn, CLOCK_50, PS2_DAT_S);


    always @(posedge CLOCK_50)  // record PS2 clock value in previous CLOCK_50 cycle
        prev_ps2_clk <= PS2_CLK_S;


    // check when PS2_CLK has changed from 1 to 0
    assign negedge_ps2_clk = (prev_ps2_clk & !PS2_CLK_S);


    // save PS2 data packet
    always @(posedge CLOCK_50) begin    // specify a 33-bit shift register
        if (Resetn == 0)
            Serial <= 33'b0;
        else if (negedge_ps2_clk) begin
            Serial[31:0] <= Serial[32:1];
            Serial[32] <= PS2_DAT_S;
        end
    end

    // 'count' ps2 data bits
    always @(posedge CLOCK_50) begin    // specify a 34-bit shift register
        if (!Resetn || Packet == 'd11)
            Packet <= 'b0;
        else if (negedge_ps2_clk) begin
            Packet <= Packet + 'b1;
        end
    end

    // used to start an object move. Key press makes scancode/release/scancode, so we check
    // for Serial[30:23] == Serial[8:1]. Key repeat makes scancode/scancode/...
    assign ps2_rec = (Packet == 'd11) && (Serial[30:23] == Serial[8:1]);


    // ps2 scancode is in Serial[8:1]
    regn USC (Serial[8:1], Resetn, Esc, CLOCK_50, scancode);
    assign LEDR = {y_Q[2:0], canBreak_1, canPlace_1, blockExists_5, blockExists_4, blockExists_3, blockExists_2, blockExists_1};


    // select object according to which PS2 key was pressed. 
    assign O1_dir = scancode; // ps2 key identifier
	 
	 wire [nX-1:0] O1_centre_x;
	 wire [nY-1:0] O1_centre_y;
	 wire collide1, collide2, collide3, collide4, collide5, collide6, collide;
	 
	 collision Collide1 (map1, collide1, O1_centre_x, O1_centre_y, O1_dir);
	 collision Collide2 (map2, collide2, O1_centre_x, O1_centre_y, O1_dir);
	 collision Collide3 (map3, collide3, O1_centre_x, O1_centre_y, O1_dir);
	 collision Collide4 (map4, collide4, O1_centre_x, O1_centre_y, O1_dir);
	 collision Collide5 (map5, collide5, O1_centre_x, O1_centre_y, O1_dir);
	 collision Collide6 (map6, collide6, O1_centre_x, O1_centre_y, O1_dir);
	 
	 assign collide = collide1 || collide2 || collide3 || collide4 || collide5 || collide6;

		reg initialize_go_1, initialize_go_2, initialize_go_3, initialize_go_4, initialize_go_5, initialize_go_6;
		reg initial_draw_1, initial_draw_2, initial_draw_3, initial_draw_4, initial_draw_5, initial_draw_6;
		
		wire initialize_done_1, initialize_done_2, initialize_done_3, initialize_done_4, initialize_done_5, initialize_done_6;
		wire block_exist_initial_1, block_exist_initial_2, block_exist_initial_3, block_exist_initial_4, block_exist_initial_5, block_exist_initial_6;
		
		wire [9:0] initializer_x_1, initializer_x_2, initializer_x_3, initializer_x_4, initializer_x_5, initializer_x_6; // coordinates to draw the block in the initialize phase.
		wire [8:0] initializer_y_1, initializer_y_2, initializer_y_3, initializer_y_4, initializer_y_5, initializer_y_6;
		
		object_map_DRAW initializer1 (Resetn, CLOCK_50, initialize_go_1, initialize_done_1, map1, block_exist_initial_1, initializer_x_1, initializer_y_1);
		object_map_DRAW initializer2 (Resetn, CLOCK_50, initialize_go_2, initialize_done_2, map2, block_exist_initial_2, initializer_x_2, initializer_y_2);
		object_map_DRAW initializer3 (Resetn, CLOCK_50, initialize_go_3, initialize_done_3, map3, block_exist_initial_3, initializer_x_3, initializer_y_3);
		object_map_DRAW initializer4 (Resetn, CLOCK_50, initialize_go_4, initialize_done_4, map4, block_exist_initial_4, initializer_x_4, initializer_y_4);
		object_map_DRAW initializer5 (Resetn, CLOCK_50, initialize_go_5, initialize_done_5, map5, block_exist_initial_5, initializer_x_5, initializer_y_5);
		object_map_DRAW initializer6 (Resetn, CLOCK_50, initialize_go_6, initialize_done_6, map6, block_exist_initial_6, initializer_x_6, initializer_y_6);
		
		
    // FSM state table

    always @ (*)
        case (y_Q)
            A:  if (SW[0] == 1) Y_D = F; 			// Idle
				else if (!ps2_rec) Y_D = A; 		
				else if (win_con) Y_D = R;
                else Y_D = B;
            B:  Y_D = E;        					// enable scancode register
			E: 	if (collide) Y_D = A; 				// Collision check
				else Y_D = C;
            C:  Y_D = D;        					// send step signal to object
            D:  if (done == 1'b0) Y_D = D;
                else Y_D = A;
			// Initializer 1
			F:	if (block_exist_initial_1) Y_D = G; 	// Count and find a block
				else if (initialize_done_1) Y_D = H;	
				else Y_D = F;
			G: if (!Block_done_1) Y_D = G; 			// Draw the block
				else Y_D = F;								// Go back and find another block
				
			// Initializer 2
			H: if (block_exist_initial_2) Y_D = I; 	// Count and find a block 
				else if (initialize_done_2) Y_D = J;
				else Y_D = H;
			I: if (!Block_done_2) Y_D = I;
				else Y_D = H;
			
			// Initializer 3
			J: if (block_exist_initial_3) Y_D = K;		// Count and find a block
				else if (initialize_done_3) Y_D = L;
				else Y_D = J;
			K: if (!Block_done_3) Y_D = K;
				else Y_D = J;
			
			// Initializer 4
			L:	if (block_exist_initial_4) Y_D = M;		// Count and find a block
				else if (initialize_done_4) Y_D = N;
				else Y_D = L;
			
			M: if (!Block_done_4) Y_D = M;
				else Y_D = L;
			
			// Initializer 5
			N: if (block_exist_initial_5) Y_D = O;		// Count and find a block
				else if (initialize_done_5) Y_D = P;
				else Y_D = N;
			
			O: if (!Block_done_5) Y_D = O;
				else Y_D = N;
			
			// Initializer 6
			P: if (block_exist_initial_6) Y_D = Q;		// Count and find a block
				else if (initialize_done_6) Y_D = A;
				else Y_D = P;
			
			Q: if (!Block_done_6) Y_D = Q;
				else Y_D = P;
			
			R: Y_D = R;											// Game win
				
            default: Y_D = A;
        endcase

    // FSM outputs
    always @ (*)
    begin
	 
        // default assignments
        Esc = 1'b0; step = 1'b0; 
		  initialize_go_1 = 1'b0; initialize_go_2 = 1'b0; initialize_go_3 = 1'b0; initialize_go_4 = 1'b0; initialize_go_5 = 1'b0; initialize_go_6 = 1'b0;
		  initial_draw_1 = 1'b0; initial_draw_2 = 1'b0; initial_draw_3 = 1'b0; initial_draw_4 = 1'b0; initial_draw_5 = 1'b0; initial_draw_6 = 1'b0;
		  win_draw = 1'b0;
        case (y_Q)
            A:  ;
            B:  Esc = 1'b1;
            C:  step = 1'b1;  
            D:  ;
			E:  ;
			F:  initialize_go_1 = 1'b1;
			G:  initial_draw_1 = 1'b1; 
			H:  initialize_go_2 = 1'b1;
			I:  initial_draw_2 = 1'b1;
			J:  initialize_go_3 = 1'b1;
			K:  initial_draw_3 = 1'b1;
			L:	 initialize_go_4 = 1'b1;
			M:  initial_draw_4 = 1'b1;
			N:  initialize_go_5 = 1'b1;
			O:  initial_draw_5 = 1'b1;
			P:  initialize_go_6 = 1'b1;
			Q:  initial_draw_6 = 1'b1;
			R:  win_draw = 1'b1;
        endcase
    end

    // FSM state FFs
    always @(posedge CLOCK_50)
        if (!Resetn)
            y_Q <= A;
        else
            y_Q <= Y_D;

    // instantiate object 1
    object O1 (Resetn, CLOCK_50, 1'b0, step, O1_dir, O1_x, O1_y, O1_color, O1_write, O1_done, O1_centre_x, O1_centre_y);
        defparam O1.LEFT  = 8'h1C;  // 'a'
        defparam O1.RIGHT = 8'h23;  // 'd'
        defparam O1.UP    = 8'h1D;  // 'w'
        defparam O1.DOWN =  8'h1B;  // 's'
        defparam O1.INIT_FILE = "./MIF/raccoon.mif";

    // These are used to store the initial (top left coordinate) of the block being drawn.

	wire [nX-1:0] xBlock;
	wire [nY-1:0] yBlock;
	
	wire blockExists_1, blockExists_2, blockExists_3, blockExists_4, blockExists_5, blockExists_6;
	wire [2:0] blockTypeOut_1, blockTypeOut_2, blockTypeOut_3, blockTypeOut_4, blockTypeOut_5, blockTypeOut_6;
	wire [10:0] addr_1, addr_2, addr_3, addr_4, addr_5, addr_6;
	
	object_map_READ (Resetn, CLOCK_50, 1'b1, map1, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_1, 3'd1, blockTypeOut_1, addr_1, xBlock, yBlock);
	object_map_READ (Resetn, CLOCK_50, 1'b1, map2, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_2, 3'd2, blockTypeOut_2, addr_2);
	object_map_READ (Resetn, CLOCK_50, 1'b1, map3, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_3, 3'd3, blockTypeOut_3, addr_3);
	object_map_READ (Resetn, CLOCK_50, 1'b1, map4, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_4, 3'd4, blockTypeOut_4, addr_4);
	object_map_READ (Resetn, CLOCK_50, 1'b1, map5, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_5, 3'd5, blockTypeOut_5, addr_5);
	object_map_READ (Resetn, CLOCK_50, 1'b1, map6, O1_centre_x - 10'd8, O1_centre_y - 9'd8, blockExists_6, 3'd6, blockTypeOut_6, addr_6);
	
	wire [2:0] blockTypePlayer = (blockExists_1) ? 3'd1 : 
										  (blockExists_2) ? 3'd2 : 
										  (blockExists_3) ? 3'd3 : 
										  (blockExists_4) ? 3'd4 : 
										  (blockExists_5) ? 3'd5 : 
										  (blockExists_6) ? 3'd6 : 
										  3'd0;
	
	wire canPlace_1, canPlace_2, canPlace_3, canPlace_4, canPlace_5, canPlace_6;
	wire canBreak_1, canBreak_2, canBreak_3, canBreak_4, canBreak_5, canBreak_6;
	wire [3:0] inv_count_1, inv_count_2, inv_count_3, inv_count_4, inv_count_5, inv_count_6;
	
	inventoryCounter counter1 (Resetn, CLOCK_50, SW1 | KEY0, KEY0, SW1, blockTypePlayer, inv_count_1, canPlace_1, canBreak_1);
		defparam counter1.BLOCKTYPE = 3'b001;
	inventoryCounter counter2 (Resetn, CLOCK_50, SW2 | KEY0, KEY0, SW2, blockTypePlayer, inv_count_2, canPlace_2, canBreak_2);
		defparam counter2.BLOCKTYPE = 3'b010;
	inventoryCounter counter3 (Resetn, CLOCK_50, SW3 | KEY0, KEY0, SW3, blockTypePlayer, inv_count_3, canPlace_3, canBreak_3);
		defparam counter3.BLOCKTYPE = 3'b011;
	inventoryCounter counter4 (Resetn, CLOCK_50, SW4 | KEY0, KEY0, SW4, blockTypePlayer, inv_count_4, canPlace_4, canBreak_4);
		defparam counter4.BLOCKTYPE = 3'b100;
	inventoryCounter counter5 (Resetn, CLOCK_50, SW5 | KEY0, KEY0, SW5, blockTypePlayer, inv_count_5, canPlace_5, canBreak_5);
		defparam counter5.BLOCKTYPE = 3'b101;
	inventoryCounter counter6 (Resetn, CLOCK_50, SW6 | KEY0, KEY0, SW6, blockTypePlayer, inv_count_6, canPlace_6, canBreak_6);
		defparam counter6.BLOCKTYPE = 3'b110;
	
	
	
	wire [nX-1:0] happy_x = (SW1 | SW2 | SW3 | SW4 | SW5 | SW6) ? xBlock :						// Draw location is the gridded player location if drawing a block
									(initial_draw_1) ? initializer_x_1 :							// Draw location is the initializer location if initializing
									(initial_draw_2) ? initializer_x_2 :
									(initial_draw_3) ? initializer_x_3 :
									(initial_draw_4) ? initializer_x_4 :
									(initial_draw_5) ? initializer_x_5 :
									(initial_draw_6) ? initializer_x_6 :
									xBlock;														// Default to player gridded
	wire [nY-1:0] happy_y = (SW1 | SW2 | SW3 | SW4 | SW5 | SW6) ? yBlock :
									(initial_draw_1) ? initializer_y_1 :
									(initial_draw_2) ? initializer_y_2 :
									(initial_draw_3) ? initializer_y_3 :
									(initial_draw_4) ? initializer_y_4 :
									(initial_draw_5) ? initializer_y_5 :
									(initial_draw_6) ? initializer_y_6 :
									yBlock;
	
	wire [nX-1:0] Block_x_1, Block_x_2, Block_x_3, Block_x_4, Block_x_5, Block_x_6, Block_x_7;
	wire [nY-1:0] Block_y_1, Block_y_2, Block_y_3, Block_y_4, Block_y_5, Block_y_6, Block_y_7;
	wire [8:0] Block_color_1, Block_color_2, Block_color_3, Block_color_4, Block_color_5, Block_color_6, Block_color_7;
	wire Block_write_1, Block_write_2, Block_write_3, Block_write_4, Block_write_5, Block_write_6, Block_write_7;
	wire Block_done_1, Block_done_2, Block_done_3, Block_done_4, Block_done_5, Block_done_6, Block_done_7;
	
	
	
	blockObject dirt (Resetn, CLOCK_50, (SW1 & canPlace_1) | initial_draw_1, Block_x_1, Block_y_1, Block_color_1, Block_write_1, Block_done_1, happy_x, happy_y, KEY0 & canBreak_1);
		defparam dirt.INIT_FILE = "MIF/wood.mif";
	blockObject cake (Resetn, CLOCK_50, (SW2 & canPlace_2) | initial_draw_2, Block_x_2, Block_y_2, Block_color_2, Block_write_2, Block_done_2, happy_x, happy_y, KEY0 & canBreak_2);
		defparam cake.INIT_FILE = "MIF/stone.mif";
	blockObject stone (Resetn, CLOCK_50, (SW3 & canPlace_3) | initial_draw_3, Block_x_3, Block_y_3, Block_color_3, Block_write_3, Block_done_3, happy_x, happy_y, KEY0 & canBreak_3);
		defparam stone.INIT_FILE = "MIF/dirt.mif";
	blockObject gold (Resetn, CLOCK_50, (SW4 & canPlace_4) | initial_draw_4, Block_x_4, Block_y_4, Block_color_4, Block_write_4, Block_done_4, happy_x, happy_y, KEY0 & canBreak_4);
		defparam gold.INIT_FILE = "MIF/tomato1.mif";
	blockObject hay (Resetn, CLOCK_50, (SW5 & canPlace_5) | initial_draw_5, Block_x_5, Block_y_5, Block_color_5, Block_write_5, Block_done_5, happy_x, happy_y, KEY0 & canBreak_5);
		defparam hay.INIT_FILE = "MIF/gold.mif";
	blockObject wood (Resetn, CLOCK_50, (SW6 & canPlace_6) | initial_draw_6, Block_x_6, Block_y_6, Block_color_6, Block_write_6, Block_done_6, happy_x, happy_y, KEY0 & canBreak_6);
		defparam wood.INIT_FILE = "MIF/cake.mif";
	
	wire win_con;
	win_con (map1, map2, map3, map4, map5, map6, win_con);
	reg win_draw;
	
	blockObject happy2 (Resetn, CLOCK_50, win_draw, Block_x_7, Block_y_7, Block_color_7, Block_write_7, Block_done_7, O1_centre_x - 10'd8, O1_centre_y - 9'd8, KEY0);
		defparam happy2.INIT_FILE = "MIF/raccoonhappy.mif";
	
	// This is to specify whether to place or break a block
	wire place_break = (SW1 == 1'b1) ? 1'b1 : // Press SW1 to place a block type 1
						(SW2 == 1'b1) ? 1'b1 : // Press SW2 to place a block type 2
						(SW3 == 1'b1) ? 1'b1 : // Press SW3 to place a block type 3
						(SW4 == 1'b1) ? 1'b1 : // Press SW4 to place a block type 4
						(SW5 == 1'b1) ? 1'b1 : // Press SW5 to place a block type 5
						(SW6 == 1'b1) ? 1'b1 : // Press SW6 to place a block type 6
							 (KEY0 == 1'b1) ? 1'b0 : // Press KEY0 to break a block
							 1'b0;
	
	// This code block below is to avoid stacking of blocks
	wire write_enable_1 = (KEY0 & canBreak_1) | (SW1 & canPlace_1);
	wire write_enable_2 = (KEY0 & canBreak_2) | (SW2 & canPlace_2);
	wire write_enable_3 = (KEY0 & canBreak_3) | (SW3 & canPlace_3);
	wire write_enable_4 = (KEY0 & canBreak_4) | (SW4 & canPlace_4);
	wire write_enable_5 = (KEY0 & canBreak_5) | (SW5 & canPlace_5);
	wire write_enable_6 = (KEY0 & canBreak_6) | (SW6 & canPlace_6);
	
	wire data_1 = SW1 && ~KEY0;
	wire data_2 = SW2 && ~KEY0;
	wire data_3 = SW3 && ~KEY0;
	wire data_4 = SW4 && ~KEY0;
	wire data_5 = SW5 && ~KEY0;
	wire data_6 = SW6 && ~KEY0;
	
	object_map_WRITE_1 W1 (Resetn, CLOCK_50, write_enable_1, xBlock, yBlock, data_1, map1);
	object_map_WRITE_2 W2 (Resetn, CLOCK_50, write_enable_2, xBlock, yBlock, data_2, map2);
	object_map_WRITE_3 W3 (Resetn, CLOCK_50, write_enable_3, xBlock, yBlock, data_3, map3);
	object_map_WRITE_4 W4 (Resetn, CLOCK_50, write_enable_4, xBlock, yBlock, data_4, map4);
	object_map_WRITE_5 W5 (Resetn, CLOCK_50, write_enable_5, xBlock, yBlock, data_5, map5);
	object_map_WRITE_6 W6 (Resetn, CLOCK_50, write_enable_6, xBlock, yBlock, data_6, map6);

    assign done = O1_done | Block_done;

	 // select a block when either
	 // 1. initializing
	 // 2. placing a block
	 // 3. breaking a block of the CORRECT type
	 wire block_sel_1 = SW1 | initial_draw_1 | (KEY0 & canBreak_1);
	 wire block_sel_2 = SW2 | initial_draw_2 | (KEY0 & canBreak_2);
	 wire block_sel_3 = SW3 | initial_draw_3 | (KEY0 & canBreak_3);
	 wire block_sel_4 = SW4 | initial_draw_4 | (KEY0 & canBreak_4);
	 wire block_sel_5 = SW5 | initial_draw_5 | (KEY0 & canBreak_5);
	 wire block_sel_6 = SW6 | initial_draw_6 | (KEY0 & canBreak_6);
	 
	wire block_active = SW1 | SW2 | SW3 | SW4 | SW5 | SW6 | KEY0 | initial_draw_1 | initial_draw_2 | initial_draw_3 | initial_draw_4 | initial_draw_5 | initial_draw_6 | win_draw;
	
	assign Block_x = 	(win_draw) ? Block_x_7 :
						(block_sel_1) ? Block_x_1 :
						(block_sel_2) ? Block_x_2 :
						(block_sel_3) ? Block_x_3 :
						(block_sel_4) ? Block_x_4 :
						(block_sel_5) ? Block_x_5 :
						(block_sel_6) ? Block_x_6 :
						
						Block_x_1;
						
	assign Block_y = 	(win_draw) ? Block_y_7 :
						(block_sel_1) ? Block_y_1 :
						(block_sel_2) ? Block_y_2 :
						(block_sel_3) ? Block_y_3 :
						(block_sel_4) ? Block_y_4 :
						(block_sel_5) ? Block_y_5 :
						(block_sel_6) ? Block_y_6 :
						Block_y_1;
	
	assign Block_color = (win_draw) ? Block_color_7 :
						(block_sel_1) ? Block_color_1 :
						(block_sel_2) ? Block_color_2 :
						(block_sel_3) ? Block_color_3 :
						(block_sel_4) ? Block_color_4 :
						(block_sel_5) ? Block_color_5 :
						(block_sel_6) ? Block_color_6 :
						Block_color_1;
	
	assign Block_write = (win_draw) ? Block_write_7 :
						(block_sel_1) ? Block_write_1 :
						(block_sel_2) ? Block_write_2 :
						(block_sel_3) ? Block_write_3 :
						(block_sel_4) ? Block_write_4 :
						(block_sel_5) ? Block_write_5 :
						(block_sel_6) ? Block_write_6 :
						Block_write_1;
	
	assign Block_done  = (win_draw) ? Block_done_7 :
						(block_sel_1) ? Block_done_1 :
						(block_sel_2) ? Block_done_2 :
						(block_sel_3) ? Block_done_3 :
						(block_sel_4) ? Block_done_4 :
						(block_sel_5) ? Block_done_5 :
						(block_sel_6) ? Block_done_6 :
						Block_done_1;
	
    // choose x, y, color, and write for one of the two objects
    assign MUX_x = (block_active) ? Block_x : O1_x ;
    assign MUX_y = (block_active) ? Block_y : O1_y ;
    assign MUX_color = (block_active) ? Block_color : O1_color;
    assign MUX_write = (block_active) ? Block_write : O1_write;


    // display PS2 data
    /*
	 hex7seg H0 (Serial[4:1], HEX0);
    hex7seg H1 (Serial[8:5], HEX1);
    hex7seg H2 (Serial[15:12], HEX2);
    hex7seg H3 (Serial[19:16], HEX3);
    hex7seg H4 (Serial[26:23], HEX4);
    hex7seg H5 (Serial[30:27], HEX5);
	 */
	 
	 hex7seg H0 (inv_count_1, HEX0);
	 hex7seg H1 (inv_count_2, HEX1);
	 hex7seg H2 (inv_count_3, HEX2);
	 hex7seg H3 (inv_count_4, HEX3);
	 hex7seg H4 (inv_count_5, HEX4);
	 hex7seg H5 (inv_count_6, HEX5);


    // connect to VGA controller

    vga_adapter VGA (
		.resetn(Resetn),
		.clock(CLOCK_50),
		.color(MUX_color),
		.x(MUX_x),
		.y(MUX_y),
		.write(MUX_write),
		.VGA_R(VGA_R),
		.VGA_G(VGA_G),
		.VGA_B(VGA_B),
		.VGA_HS(VGA_HS),
		.VGA_VS(VGA_VS),
		.VGA_BLANK_N(VGA_BLANK_N),
		.VGA_SYNC_N(VGA_SYNC_N),
		.VGA_CLK(VGA_CLK));

	defparam VGA.BACKGROUND_IMAGE = "./MIF/bakebg.mif" ;
endmodule



// syncronizer, implemented as two FFs in series
module sync(D, Resetn, Clock, Q);
    input wire D;
    input wire Resetn, Clock;
    output reg Q;

    reg Qi; // internal node

    always @(posedge Clock)
        if (Resetn == 0) begin
            Qi <= 1'b0;
            Q <= 1'b0;
        end

        else begin
            Qi <= D;
            Q <= Qi;
        end

endmodule



// n-bit up/down-counter with reset, load, enable, and direction control

module upDn_count (R, Clock, Resetn, L, E, Dir, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Clock, Resetn, E, L, Dir;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= {n{1'b0}};
        else if (L == 1)
            Q <= R;
        else if (E)
            if (Dir)
                Q <= Q + {{n-1{1'b0}},1'b1};
            else
                Q <= Q - {{n-1{1'b0}},1'b1};
endmodule



module hex7seg (hex, display);
    input wire [3:0] hex;
    output reg [6:0] display;



    /*
     *       0  
     *      ---  
     *     |   |
     *    5|   |1
     *     | 6 |
     *      ---  
     *     |   |
     *    4|   |2
     *     |   |
     *      ---  
     *       3  
     */

    always @ (hex)

        case (hex)
            4'h0: display = 7'b1000000;
            4'h1: display = 7'b1111001;
            4'h2: display = 7'b0100100;
            4'h3: display = 7'b0110000;
            4'h4: display = 7'b0011001;
            4'h5: display = 7'b0010010;
            4'h6: display = 7'b0000010;
            4'h7: display = 7'b1111000;
            4'h8: display = 7'b0000000;
            4'h9: display = 7'b0011000;
            4'hA: display = 7'b0001000;
            4'hB: display = 7'b0000011;
            4'hC: display = 7'b1000110;
            4'hD: display = 7'b0100001;
            4'hE: display = 7'b0000110;
            4'hF: display = 7'b0001110;
        endcase

endmodule



// implements a movable object

module object (Resetn, Clock, go, ps2_rec, dir, VGA_x, VGA_y, VGA_color, VGA_write, done, x_centre, y_centre);
    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;
	
    // by default, use offsets to center the object on the VGA display
    parameter XOFFSET = 630;
    parameter YOFFSET = 10;
    parameter LEFT = 2'b00 /*'a'*/, RIGHT = 2'b11/*'s'*/, UP = 2'b01/*'w'*/, DOWN = 2'b10/*'z'*/;
    parameter xOBJ = 4, yOBJ = 4;   // object size is 2^xOBJ x 2^yOBJ
    parameter BOX_SIZE_X = 1 << xOBJ;
    parameter BOX_SIZE_Y = 1 << yOBJ;
    parameter Mn = xOBJ + yOBJ; // address lines needed for the object memory
    parameter INIT_FILE = "./MIF/object_mem_16_16_9.mif";

    // state names for the FSM that draws the object
    parameter A = 3'b000, B = 3'b001, C = 3'b010, D = 3'b011, E = 3'b100,
              F = 3'b101, G = 3'b110, H = 3'b111;

    input wire Resetn, Clock;
    input wire go;                              // can be used to draw at initial position
    input wire ps2_rec;                         // PS2 data received
    input wire [7:0] dir;                       // movement direction
	output wire [nX-1:0] VGA_x;                 // for syncing with object memory
	output wire [nY-1:0] VGA_y;                 // for syncing with object memory
	output wire [8:0] VGA_color;                // used to draw pixels

    output wire VGA_write;                      // pixel write control

    output reg done;                            // done drawing cycle

output wire [nX-1:0] x_centre;

output wire [nY-1:0] y_centre;



wire [nX-1:0] X, X0;    // starting X location 
wire [nY-1:0] Y, Y0;    // starting Y location 
wire [nX-1:0] size_x = BOX_SIZE_X;   // store the X size (must be power of 2)
wire [nY-1:0] size_y = BOX_SIZE_Y;   // store the Y size
    wire [xOBJ-1:0] XC;                  // used to access object memory
    wire [yOBJ-1:0] YC;                  // used to access object memory
    reg write, Lxc, Lyc, Exc, Eyc;       // object control signals
    reg erase;                           // erase/draw object
    wire Right, Left, Up, Down;          // object direction
    reg Lx, Ly, Ex, Ey;                  // object counter controls
    reg [2:0] y_Q, Y_D;                  // FSM
    
wire [8:0] obj_color;    // object pixel colors, read from memory


    // object (x,y) location. For x, counter will be enabled when moving L/R, increment
    // for R, decrement for L. For y, counter will be enabled when moving U/D, increment 
    // for D, decrement for U
    assign X0 = XOFFSET;
    assign Y0 = YOFFSET;

    upDn_count UX (X0, Clock, Resetn, Lx, Ex, Right, X);
        defparam UX.n = nX;
    upDn_count UY (Y0, Clock, Resetn, Ly, Ey, Down, Y);
        defparam UY.n = nY;

    // these counter are used to generate (x,y) coordinates to read the object's pixels
    upDn_count U3 ({xOBJ{1'd0}}, Clock, Resetn, Lxc, Exc, 1'b1, XC); // object column counter
        defparam U3.n = xOBJ;
    upDn_count U4 ({yOBJ{1'd0}}, Clock, Resetn, Lyc, Eyc, 1'b1, YC); // object row counter
        defparam U4.n = yOBJ;

    // these signals are used to enable the (x,y) object location counters and to make these 
    // counters increment or decrement
    assign Left = (dir == LEFT);
    assign Right = (dir == RIGHT);
    assign Up = (dir == UP);
    assign Down = (dir == DOWN);

    // FSM state table
    always @ (*)
        case (y_Q)
            A:  Y_D = B;                        // load (x,y) location counters
            B:  if (go) Y_D = F;                // pushbutton KEY pressed to show object
                else if (ps2_rec) Y_D = C;      // PS2 key received to move object
                else Y_D = B;                   // wait
            C:  if (XC != size_x-1) Y_D = C;    // erase row of object
                else Y_D = D;
            D:  if (YC != size_y-1) Y_D = C;    // next row of object to erase
                else Y_D = E;                   // done erase cycle
            E:  Y_D = F;                        // +/- (x,y)
            F:  if (XC != size_x-1) Y_D = F;    // draw row of object
                else Y_D = G;
            G:  if (YC != size_y-1) Y_D = F;    // next row of object to draw
                else Y_D = H;                   // done draw cycle
            H:  if (go) Y_D = H;                // wait for KEY press
                else Y_D = B;
            default: Y_D = A;
        endcase

    // FSM outputs

    always @ (*)
    begin
        // default assignments
        Lx = 1'b0; Ly = 1'b0; Ex = 1'b0; Ey = 1'b0; write = 1'b0; 
        Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; erase = 1'b0; done = 1'b0;
        case (y_Q)
            A:  begin Lx = 1'b1; Ly = 1'b1; end                   // load (X,Y) counters
            B:  begin Lxc = 1'b1; Lyc = 1'b1; end                 // load (XC,YC) counters
            C:  begin Exc = 1'b1; write = 1'b1; erase = 1'b1; end // enable XC, write pixel
            D:  begin Lxc = 1'b1; Eyc = 1'b1; erase = 1'b1; end   // load XC, enable YC
            // state E is reached after erasing the object. Now, move and draw the object
            E:  begin Ex = Right | Left; Ey = Up | Down; end      // move L/R or U/D
            F:  begin Exc = 1'b1; write = 1'b1; end               // enable XC, write pixel
            G:  begin Lxc = 1'b1; Eyc = 1'b1; end                 // load XC, enable YC
            H:  done = 1'b1;
		endcase

    end



    // FSM state FFs
    always @(posedge Clock)
        if (!Resetn)
            y_Q <= 3'b0;
        else
            y_Q <= Y_D;
	
    // read a pixel color from the object memory. We can use {YC,XC} because the x dimension
    // of the object memory is a power of 2
    object_mem U6 ({YC,XC}, Clock, obj_color);
        defparam U6.n = 9;
        defparam U6.Mn = xOBJ + yOBJ;
        defparam U6.INIT_FILE = INIT_FILE;

    // compute the (x,y) location of the current pixel to be drawn (or erased). We subtract
    // half the object's width and height because we want the objec to be centered at its 
    // original (x,y) location. We add (Xc,YC) to form the correct address of the pixel. The
    // object memory takes one clock cycle to provide data, so we register the computed (x,y)
    // location to remain synchronized

    regn U7 (X - (size_x >> 1) + XC, Resetn, 1'b1, Clock, VGA_x);
        defparam U7.n = nX;
    regn U8 (Y - (size_y >> 1) + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam U8.n = nY;

    // synchronize write signal with VGA_x, VGA_y, VGA_color 
    regn U9 (write, Resetn, 1'b1, Clock, VGA_write);
        defparam U9.n = 1;


    // use the background color (when erasing), or the object color when drawing
    // (black background is assumed below)
    assign VGA_color = erase ? {9'h6B} : obj_color;

	assign x_centre = X;
	assign y_centre = Y;
endmodule



module coordinateConverter(new_X, new_Y, XC, YC);

	parameter nX = 10;
	parameter nY = 9;
	input [nX-1:0]XC;
	output [nX-1:0] new_X;
	input [nY-1:0]YC;
	output [nY-1:0] new_Y;

	assign new_X = XC - XC % 10'd16;
	assign new_Y = YC - 9'd16 - YC % 9'd16;

endmodule

module collision(map, collide, O1_centre_x, O1_centre_y, O1_dir);

	parameter nX = 10;
	parameter nY = 9;
	
	parameter LEFT  = 8'h1C;  // 'a'
   parameter RIGHT = 8'h23;  // 'd'
   parameter UP    = 8'h1D;  // 'w'
   parameter DOWN =  8'h1B;  // 's'
	
	
	input wire [7:0] O1_dir;
    input wire [1199:0] map;
	input wire [nX-1:0] O1_centre_x;
	input wire [nY-1:0] O1_centre_y;
    output wire collide;

    wire [nX-1:0] O1_centre_x_new, left_x, right_x; // coordinates for collision check
	wire [nY-1:0] O1_centre_y_new, top_y, bottom_y;

    // Step the object in the correct direction once, get new coordinates. 
	assign O1_centre_x_new = (O1_dir == RIGHT) ? O1_centre_x + 10'd1 :
									(O1_dir == LEFT) ? O1_centre_x - 10'd1 :
										O1_centre_x;

	assign O1_centre_y_new = (O1_dir == DOWN) ? O1_centre_y + 9'd1 :
									(O1_dir == UP) ? O1_centre_y - 9'd1 :
									O1_centre_y;

 
    // calculate the left, right, top, bottom of the block
	assign left_x = O1_centre_x_new - 10'd8;
	assign right_x = O1_centre_x_new + 10'd8 - 10'd1;
	assign top_y = O1_centre_y_new - 9'd8;
	assign bottom_y = O1_centre_y_new + 9'd8 - 9'd1;

    // convert the pixel coordinate into the grid coordinates.
	wire[5:0] left_grid_x = left_x / 10'd16;
	wire[5:0] right_grid_x = right_x / 10'd16;
	wire[4:0] top_grid_y = top_y / 9'd16;
	wire[4:0] bottom_grid_y = bottom_y / 9'd16;

 
    // check if there is a block on the top left, top right, bottom left, bottom right corner.
	wire top_left_corner = map[top_grid_y * 40 + left_grid_x];
	wire top_right_corner = map[top_grid_y * 40 + right_grid_x];
	wire bottom_left_corner = map[bottom_grid_y * 40 + left_grid_x];
	wire bottom_right_corner = map[bottom_grid_y * 40 + right_grid_x];

    // if any of the coordinates have a clock, block collides.
	assign collide = top_left_corner || top_right_corner || bottom_left_corner || bottom_right_corner || 
	left_x < 192 && top_y < 128;

endmodule

module win_con (map1, map2, map3, map4, map5, map6, win_con);
	
	input wire [1199:0] map1, map2, map3, map4, map5, map6;
	output wire win_con = 
	(map3[8 * 40 + 16] == 1'b1 && map3[8 * 40 + 17] == 1'b1 && map3[8 * 40 + 18] == 1'b1 && map3[8 * 40 + 19] == 1'b1 && map3[8 * 40 + 20] == 1'b1 && map3[7 * 40 + 17] == 1'b1 && map3[7 * 40 + 19] == 1'b1 &&
	 map2[7 * 40 + 16] == 1'b1 && map2[7 * 40 + 18] == 1'b1 && map2[7 * 40 + 20] == 1'b1 && map2[6 * 40 + 16] == 1'b1 && map2[6 * 40 + 17] == 1'b1 && map2[6 * 40 + 18] == 1'b1 && map2[6 * 40 + 19] == 1'b1 && map2[6 * 40 + 20] == 1'b1 &&
	 map4[5 * 40 + 16] == 1'b1 && map4[5 * 40 + 20] == 1'b1 &&
	 map6[5 * 40 + 18] == 1'b1 && map6[4 * 40 + 18] == 1'b1 &&
	 map5[3 * 40 + 18] == 1'b1) ? 1'b1 : 1'b0;
	
	
endmodule

// THIS IS A SWITCH DEBOUNCER TAKEN FROM AN ONLINE SOURCE
// NOT ORIGINAL CODE! CITATIONS BELOW
// fpga4student.com: FPGA projects, Verilog projects, VHDL projects
// Verilog code for button debouncing on FPGA
// debouncing module without creating another clock domain
// by using clock enable signal 
module debounce(input pb_1,clk,output pb_out);
	wire slow_clk_en;
	wire Q1,Q2,Q2_bar,Q0;
	clock_enable u1(clk,slow_clk_en);
	my_dff_en d0(clk,slow_clk_en,pb_1,Q0);

	my_dff_en d1(clk,slow_clk_en,Q0,Q1);
	my_dff_en d2(clk,slow_clk_en,Q1,Q2);
	assign Q2_bar = ~Q2;
	assign pb_out = Q1 & Q2_bar;
endmodule
	
// Slow clock enable for debouncing button 
module clock_enable(input Clk_100M,output slow_clk_en);
	reg [26:0]counter=0;
	always @(posedge Clk_100M)
	begin
		counter <= (counter>=249999)?0:counter+1;
	end
	assign slow_clk_en = (counter == 249999)?1'b1:1'b0;
	
endmodule

// D-flip-flop with clock enable signal for debouncing module 
module my_dff_en(input DFF_CLOCK, clock_enable,D, output reg Q=0);
	  always @ (posedge DFF_CLOCK) begin
	  if(clock_enable==1) 
			Q <= D;
	  end
endmodule 
