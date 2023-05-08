package chip8

import fmt "core:fmt"
import os "core:os"
import m "core:math/linalg/hlsl"
import rl "vendor:raylib"
import rand "core:math/rand"

ram : [4096]byte

//this will contain the hex charas 15 
reserved_range : m.uint2 = m.uint2{0x0,0x200} 

//start programs at 0x200
pc : u16 = 0x200
sp : u16 = 0x0
is_eti : bool = false

//registers
//VF is used to store the carry (additions) and borrow (subtractions) flags, and should not be used by the programs directly.
v : [16]u16
//two special purpose registers
//deltay timer
dt : u16
//sound timer
st : u16
//index register
ir : u16

//stack
stack : [16]u16

//lifo proc for the stack
push :: proc(val : u16){
	stack[sp] = val
	sp += 1
	return
}

pop :: proc()->u16{
	if sp > 0{
		sp -= 1
	}
	value := stack[sp]
	return value
}

keymap : [16]byte

//keymap enum
keymap_enum :: enum{
	zero = 0x0,
	one = 0x1,
	two = 0x2,
	three = 0x3,
	four = 0x4,
	five = 0x5,
	six = 0x6,
	seven = 0xe,
	eight = 0x8,
	nine = 0x9,
	a = 0xa,
	b = 0xb,
	c = 0xc,
	d = 0xd,
	e = 0xe,
	f = 0xf,
}

//display 
display : [64*32]byte
//0,0 to pleft 63,31 bottom right

//opcodes enum
opcodes :: enum{
	cls = 0x00E0,
	ret = 0x00EE,
	jp = 0x1000,
	call = 0x2000,
	se = 0x3000,
	sne = 0x4000,
	se2 = 0x5000,
	ld = 0x6000,
	add = 0x7000,
	ld2 = 0x8000,
	or = 0x8001,
	and = 0x8002,
	xor = 0x8003,
	add2 = 0x8004,
	sub = 0x8005,
	shr = 0x8006,
	subn = 0x8007,
	shl = 0x800E,
	sne2 = 0x9000,
	ldi = 0xA000,
	jp2 = 0xB000,
	rnd = 0xC000,
	drw = 0xD000,
	skp = 0xE09E,
	sknp = 0xE0A1,
	ld3 = 0xF007,
	ld4 = 0xF00A,
	ld5 = 0xF015,
	ld6 = 0xF018,
	add3 = 0xF01E,
	ld7 = 0xF029,
	ld8 = 0xF033,
	ld9 = 0xF055,
	ld10 = 0xF065,
}

main :: proc(){
	//load rom from disk
	//get the rom name from the command line assume it to be the first argument
	rom_name := os.args[1]
	//open the file
	rom_file,ok := os.read_entire_file_from_filename(rom_name)
	assert(ok)

	if is_eti{
		pc = 0x600
	}

	fonts : [80]byte = {0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
	}

	ram_fonts := ram[0:80]
	for b,i in &ram_fonts{
		b = fonts[i]
	}

	//load the rom into memory
	for b,i in &rom_file{
		ram[int(pc)+i] = b
	}

	rand_num : rand.Rand
	rand.init(&rand_num,12345)

	rl.InitWindow(640,320,"chip8")
	rl.SetTargetFPS(60)
	for !rl.WindowShouldClose(){
		for nothing in 0..= 10{
		//emulate cycle
		//delay timer
		if dt > 0{
			dt -= 1
		}
		//dt value can be read into register from fx15 and fx07
		//sound timer
		if st > 0{
			//will sound buzzer when decremented
			st -= 1
		}
		//st value can be set from fx18
		//36 instructions by convention all start with even addresses
		//each instruction is 2 bytes long
		//MSB is first
		//Format is CXYN or CXNN CNNN each cahar is 4 bits c is for code group 
		//x and y are typically regisetr numbers N NN or NNN are 4 8 or 12  bit literal numbers used to set vavlues for further 
		///identificatiion within a group
		//pc is set to 0x200 at start of program

		//CLS
		//clears the display
		//00E0

		opcode_msb := (u16(ram[pc]) << 8)
		opcode_lsb := (u16(ram[pc + 1]))
		opcode : u16 = (u16)(opcode_msb | opcode_lsb)

		opcode_first_byte : u8 = ram[pc]
		opcode_second_byte : u8 = ram[pc + 1]
		testnum := u8(0x9)

		opcode_first_byte = ((opcode_first_byte & 0xF0) >> 4)

		pc += 2

		//errorcheck next opcode 
		/*
		nopcode_msb := (u16(ram[pc]) << 8)
		nopcode_lsb := (u16(ram[pc + 1]))
		nopcode : u16 = (u16)(nopcode_msb | nopcode_lsb)
		assert(nopcode != 0)
		*/
		assert(opcode != 0)
		//fmt.println("opcode: ", opcode)
		//fmt.println("nopcode: ", nopcode)
		//fmt.println("opcode_first_byte: ", opcode_first_byte)
		//fmt.printf("opcode: %x %x\n", opcode_first_byte, opcode_second_byte)
		//fmt.printf("%x %x\n", opcode_first_byte, opcode_second_byte)
		//fmt.printf("NNN para : %x\n", (opcode & 0x0FFF))

		switch opcode_first_byte{
			case 0x0:{
				if opcode_second_byte == 0xE0{
					//clear display
					d_s := display[:]
					for pixel in &d_s{
						pixel = 0
					}
				}else if opcode_second_byte == 0xEE{
					//return from subroutine
					pc = pop()
				}
			}
			case 0x1:{
				//jump to address
				pc = opcode & 0x0FFF
			}
			case 0x2:{
				//call subroutine
				push(pc)
				pc = opcode & 0x0FFF
			}
			case 0x3:{
				//skip next instruction if vx == nn
				reg_num := (opcode & 0x0F00) >> 8
				reg_val := v[reg_num]
				if reg_val == (opcode & 0x00FF){
					pc += 2
				}
			}
			case 0x4:{
				//skip next instruction if vx != nn
				reg_num := (opcode & 0x0F00) >> 8
				reg_val := v[reg_num]
				test_num := (opcode & 0x00FF)
				if reg_val != test_num{
					pc += 2
				}
			}
			case 0x5:{
				//skip next instruction if vx == vy
				reg_num_x := (opcode & 0x0F00) >> 8
				reg_num_y := (opcode & 0x00F0) >> 4
				reg_val_x := v[reg_num_x]
				reg_val_y := v[reg_num_y]
				if reg_val_x == reg_val_y{
					pc += 2
				}
			}
			case 0x6:{
				//set vx to nn
				reg_num := (opcode & 0x0F00) >> 8
				v[reg_num] = (opcode & 0x00FF)
			}
			case 0x7:{
				//add nn to vx
				reg_num := (opcode & 0x0F00) >> 8
				value := (opcode & 0x00FF)
				/*
				fmt.println("add nn to vx")
				fmt.println("reg_num: ", reg_num)
				fmt.println("value: ", value)
				fmt.println("v[reg_num]: ", v[reg_num])
				*/
				//add the number together as 8 bit numbers the result is always a 256 modulo 
				v[reg_num] = (v[reg_num] + value) & 0x00FF
				//fmt.println("v[reg_num]: ", v[reg_num])
			}
			case 0x8:{
				opcode_second := opcode & 0x000F
				if opcode_second == 0x0{
					//set vx to vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = reg_val_y
				}else if opcode_second == 0x1{
					//set vx to vx | vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = reg_val_x | reg_val_y
					v[0xF] = 0
				}else if opcode_second == 0x2{
					//set vx to vx & vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = reg_val_x & reg_val_y
					v[0xF] = 0
				}else if opcode_second == 0x3{
					//set vx to vx ^ vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = reg_val_x ~ reg_val_y
					v[0xF] = 0
				}else if opcode_second == 0x4{
					//set vx to vx + vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = (reg_val_x + reg_val_y) & 0x00FF 	
					if (reg_val_x + reg_val_y) > 0xFF{
						v[0xF] = 1
					}else{
						v[0xF] = 0
					}
				}else if opcode_second == 0x5{
					//set vx to vx - vy
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = (reg_val_x - reg_val_y) % 256
					if reg_val_x > reg_val_y{
						v[0xF] = 1
					}else{
						v[0xF] = 0
					}
				}else if opcode_second == 0x6{
					//set vx to vy >> 1
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = (reg_val_y >> 1) & 0x00FF
					v[0xF] = reg_val_y & 0x01
				}
				else if opcode_second == 0x7{
					//set vx to vy - vx
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_x := v[reg_num_x]
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = (reg_val_y - reg_val_x) % 256
					if reg_val_x < reg_val_y {
						v[0xF] = 1
					}else{
						v[0xF] = 0
					}
				}
				else if opcode_second == 0xE{
					//set vx to vy << 1
					reg_num_x := (opcode & 0x0F00) >> 8
					reg_num_y := (opcode & 0x00F0) >> 4
					reg_val_y := v[reg_num_y]
					v[reg_num_x] = (reg_val_y << 1) & 0x00FF
					v[0xF] = (reg_val_y & 0x80) >> 7
				}
			}
			case 0x9:{
				//set vx to vx | vy
				reg_num_x := (opcode & 0x0F00) >> 8
				reg_num_y := (opcode & 0x00F0) >> 4
				reg_val_x := v[reg_num_x]
				reg_val_y := v[reg_num_y]
				v[reg_num_x] = reg_val_x | reg_val_y
			}
			case 0xA:{
				//set i to nnn
				ir = (opcode & 0x0FFF)
			}
			case 0xB:{
				//jump to nnn + vN where N is teh highest nibble of NNN
				//reg_num := (opcode & 0x0F00) >> 8
				//pc = (opcode & 0x0FFF) + v[reg_num]

				//jump to nnn + vN where N is teh highest nibble of NNN
				//reg_num := (opcode & 0x0F00) >> 8

				pc = (opcode & 0x0FFF) + v[0]
			}
			case 0xC:{
				//set vx to random byte & nn
				reg_num := (opcode & 0x0F00) >> 8
				rn := u16(rand.float32_range(0,255))
				v[reg_num] = (rn & (opcode & 0x00FF))
			}
			case 0xD:{
				//v[0xF] = 0
				//draw sprite at vx,vy with height n
				reg_num_x := (opcode & 0x0F00) >> 8
				reg_num_y := (opcode & 0x00F0) >> 4
				reg_val_x := (v[reg_num_x]) % 64
				reg_val_y := (v[reg_num_y]) % 32
				height := (opcode & 0x000F)
				for yline : u16= 0; yline < height; yline+=1{
					pixel := ram[ir + yline]
					ypos := (reg_val_y + yline)
					if ypos > 31{
						break
					}
					for xline : u16 = 0; xline < 8; xline +=1{
						xpos := (reg_val_x + xline)
						if xpos > 63{
							break
						}
						pos := (xpos + (ypos) * 64 )

						pixel_value := (pixel & (0x80 >> xline))
						display_value := display[pos]

						if pixel_value != 0 {
							pixel_value = 0xFF
						}
						/*
						if pixel_value != 0{
							//if display_value != 0 && pixel_value != 0{
							if display_value != 0{
								//collision flag
								display[pos] = 0
								v[0xF] = 1
							}else{
								display[pos] = 0xFF
								//v[0xF] = 0
							}
						}
						*/

						display[pos] = pixel_value ~ display_value
						if pixel_value != 0 && display_value != 0{
							//collision flag
							v[0xF] = 1
						}else{
							v[0xF] = 0
						}

						//display[pos] = display_value ~ pixel_value
						//write dispaly value with xoring the current pixel value
						/*
						//if (pixel & (0x80 >> xline)) != 0{
							//display[pos] = 0xFF ~ display[pos]
							if display[pos] == 0xFF{
								display[pos] = 0
							}else{
								display[pos] = 0xFF
							}
						//}
						*/
					}
				}
			}
			case 0xE:{
				//check for key press
				reg_num := (opcode & 0x0F00) >> 8
				reg_val := v[reg_num]
				opcode_second := opcode & 0x00FF
				//fmt.println(reg_val)
				if opcode_second == 0x9E{
					//fmt.printf("is down %v",reg_val)
					if keymap[reg_val] != 0{
						//fmt.println("key is down-------------------------")
						pc = pc + 2
					}
				}else if opcode_second == 0xA1{
					if keymap[reg_val] == 0{
						//fmt.println("key is up -------------------------- ")
						pc = pc + 2
					}
				}else{
					assert(false, "Unknown opcode")
				}
			}
			case 0xF:{
				//misc instructions
				reg_num := (opcode & 0x0F00) >> 8
				reg_val := v[reg_num]
				if (opcode & 0x00FF) == 0x07{
					v[reg_num] = dt
				}else if (opcode & 0x00FF) == 0x0A{
					//fmt.println("Check if key is holding process")
					key_press := false
					for i : u16 = 0; i < 16; i += 1{
						if keymap[i] != 0{
							v[reg_num] = i
							key_press = true
						}
					}
					if !key_press{
						pc -= 2
					}
				}else if (opcode & 0x00FF) == 0x15{
					dt = reg_val
				}else if (opcode & 0x00FF) == 0x18{
					st = reg_val
				}else if (opcode & 0x00FF) == 0x1E{
					ir += reg_val
				}else if (opcode & 0x00FF) == 0x29{
					ir = u16(reg_val * 0x5)
				}else if (opcode & 0x00FF) == 0x33{
					ram[ir] = u8(reg_val / 100)
					ram[ir + 1] = u8((reg_val / 10) % 10)
					ram[ir + 2] = u8((reg_val % 100) % 10)
				}else if (opcode & 0x00FF) == 0x55{
					x := reg_num
					tempir := ir
					for i : u16 = 0; i <= x; i += 1{
						ram[tempir] = u8(v[i])
						tempir += 1
					}
					ir = ir + u16(reg_num + 1)
				}else if (opcode & 0x00FF) == 0x65{
					x := reg_num
					tempir := ir
					for i : u16 = 0; i <= x; i += 1{
						v[i] = u16(ram[tempir])
						tempir += 1
					}
					ir = ir + u16(reg_num + 1)
				}
			}
		}

		//set keypress to keymap

		if rl.IsKeyDown(rl.KeyboardKey.ONE){
			keymap[keymap_enum.one] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.ONE){
			keymap[keymap_enum.one] = 0
		}
		/*
		if rl.IsKeyDown(rl.KeyboardKey.ZERO){
			keymap[keymap_enum.zero] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.ZERO){
			keymap[keymap_enum.zero] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.TWO){
			keymap[keymap_enum.two] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.TWO){
			keymap[keymap_enum.two] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.THREE){
			keymap[0x3] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.THREE){
			keymap[] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.FOUR){
			keymap[0x4] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.FOUR){
			keymap[0x4] = 0
		}
		*/

		if rl.IsKeyDown(rl.KeyboardKey.F){
			keymap[keymap_enum.e] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.F){
			keymap[keymap_enum.e] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.V){
			keymap[keymap_enum.f] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.V){
			keymap[keymap_enum.f] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.Z){
			keymap[keymap_enum.a] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.Z){
			keymap[keymap_enum.a] = 0
		}
	}

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

		x,y : i32
		for pixel,i in &display{
			if x == 0 && y == 0{
				rl.DrawRectangle(x,y,10,10,rl.RED)
			}else if x == 640 - 10 && y == 320 - 10{
				rl.DrawRectangle(x,y,10,10,rl.GREEN)
			}else{
				color := rl.Color{pixel,pixel,pixel,255}
				rl.DrawRectangle(x,y,10,10,color)
			}
			x += 10
			//after 32 pixels go to next line
			if x % 640 == 0{
				x = 0
				y += 10
			}
		}

		rl.EndDrawing()
	}

	rl.CloseWindow()

}
