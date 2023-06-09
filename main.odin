package chip8

import fmt "core:fmt"
import os "core:os"
import m "core:math/linalg/hlsl"
import rl "vendor:raylib"
import rand "core:math/rand"
import ma "vendor:miniaudio"
import c "core:c"
import mem "core:mem"

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
halting_keymap : [16]byte

//keymap enum
keymap_enum :: enum{
	zero = 0x0,
	one = 0x1,
	two = 0x2,
	three = 0x3,
	four = 0x4,
	five = 0x5,
	six = 0x6,
	seven = 0x7,
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

base_freq : f32 = 440
freq : f32 = base_freq
audio_freq : f32 = base_freq
old_freq : f32 = 1 
sine_idx : f32 = 0

audio_callback :: proc(buffer : rawptr,frames : c.uint){
	//TODO
	audio_freq = freq + (audio_freq - freq) * 0.95
	audio_freq += 1.0
	audio_freq -= 1.0
	incr := audio_freq / 44100.0
	d := buffer

	for i in 0..=frames - 1{
		dptr := mem.ptr_offset((^u16)(d),i)
		dptr^ = u16(32000 * m.sin_float(2 * m.PI * sine_idx)) 
		sine_idx += incr
		if sine_idx > 1{
			sine_idx -= 1
		}
	}
}

main :: proc(){
	//load rom from disk
	//get the rom name from the command line adptrssume it to be the first argument
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
rl.InitAudioDevice()

max_samples : i32 = 512
max_samples_per_update : i32 = 4096
rl.SetAudioStreamBufferSizeDefault(max_samples_per_update)

//audio stream
stream := rl.LoadAudioStream(44100,16,1)
audio_callback_proc : rl.AudioCallback = rl.AudioCallback(audio_callback)
rl.SetAudioStreamCallback(stream,audio_callback_proc)

data := make([]byte,max_samples)
write_buf := make([]byte,max_samples_per_update)

wavelength := 1

for !rl.WindowShouldClose(){
	//delay timer
	if dt > 0{
		dt -= 1
	}
	//sound timer
	if st > 0{
		st -= 1
		rl.PlayAudioStream(stream)
	}else{
		rl.StopAudioStream(stream)
	}
	loop: for nothing in 0..=10{

		opcode_msb := (u16(ram[pc]) << 8)
		opcode_lsb := (u16(ram[pc + 1]))
		opcode : u16 = (u16)(opcode_msb | opcode_lsb)

		opcode_first_byte : u8 = ram[pc]
		opcode_second_byte : u8 = ram[pc + 1]
		testnum := u8(0x9)

		opcode_first_byte = ((opcode_first_byte & 0xF0) >> 4)

		pc += 2
		//assert(opcode != 0)
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
				//COSMAC based variants reset vf to 0 before the operation
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
					v[reg_num_x] = (reg_val_x - reg_val_y) & 0x00FF
					if reg_val_x < reg_val_y{
						v[0xF] = 0
					}else{
						v[0xF] = 1
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
					v[reg_num_x] = (reg_val_y - reg_val_x) & 0x00FF
					if reg_val_x > reg_val_y {
						v[0xF] = 0
					}else{
						v[0xF] = 1
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
				if reg_val_x != reg_val_y{
					pc += 2
				}
			}
			case 0xA:{
				//set i to nnn
				ir = (opcode & 0x0FFF)
			}
			case 0xB:{
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
				v[0xF] = 0
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
						pos := (xpos + (ypos) * 64 )

						pixel_value := (pixel & (0x80 >> xline))
						if xpos > 63{
							break
						}

						display_value := display[pos]

						if pixel_value > 0 {
							pixel_value = 0xFF
						}

						display[pos] = display_value ~ pixel_value
						if pixel_value != 0 && display_value != 0{
							//collision flag
							v[0xF] = 1
						}
					}
				}
				break loop
			}
			case 0xE:{
				//check for key press
				reg_num := (opcode & 0x0F00) >> 8
				reg_val := v[reg_num]
				opcode_second := opcode & 0x00FF
				//fmt.println(reg_val)
				if opcode_second == 0x009E{
					//fmt.printf("is down %v",reg_val)
					if keymap[reg_val] != 0{
						//fmt.println("key is down-------------------------")
						pc = pc + 2
					}
				}else if opcode_second == 0x00A1{
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
					//("Check if key is holding process and released")
					key_press := false
					for i : u16 = 0; i < 16; i += 1{
						if keymap[i] != 0{
							halting_keymap[i] = 1
						}
					}
					key_press = false
					for key,i in &halting_keymap{
						//pressed and released
						if key == 1 && keymap[i] == 0{
							v[reg_num] = u16(i)
							key = 0
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
			keymap[keymap_enum.three] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.THREE){
			keymap[keymap_enum.three] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.FOUR){
			keymap[keymap_enum.four] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.FOUR){
			keymap[keymap_enum.four] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.FIVE){
			keymap[keymap_enum.five] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.FIVE){
			keymap[keymap_enum.five] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.SIX){
			keymap[keymap_enum.six] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.SIX){
			keymap[keymap_enum.six] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.SEVEN){
			keymap[keymap_enum.seven] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.SEVEN){
			keymap[keymap_enum.seven] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.EIGHT){
			keymap[keymap_enum.eight] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.EIGHT){
			keymap[keymap_enum.eight] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.NINE){
			keymap[keymap_enum.nine] = 1
		}else if rl.IsKeyReleased(rl.KeyboardKey.NINE){
			keymap[keymap_enum.nine] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.F){
			keymap[keymap_enum.f] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.F){
			keymap[keymap_enum.f] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.E){
			keymap[keymap_enum.e] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.E){
			keymap[keymap_enum.e] = 0
		}

		if rl.IsKeyDown(rl.KeyboardKey.A){
			keymap[keymap_enum.a] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.A){
			keymap[keymap_enum.a] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.B){
			keymap[keymap_enum.b] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.B){
			keymap[keymap_enum.b] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.C){
			keymap[keymap_enum.c] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.C){
			keymap[keymap_enum.c] = 0
		}
		if rl.IsKeyDown(rl.KeyboardKey.D){
			keymap[keymap_enum.d] = 1
		}else if rl.IsKeyUp(rl.KeyboardKey.D){
			keymap[keymap_enum.d] = 0
		}

	}//for execute

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	x,y : i32
	for pixel,i in &display{
		color := rl.Color{pixel,pixel,pixel,255}
		rl.DrawRectangle(x,y,10,10,color)
		x += 10
		//after 32 pixels go to next line
		if x % 640 == 0{
			x = 0
			y += 10
		}
	}

	rl.EndDrawing()
}//ishwindowd clow

rl.CloseWindow()

}//main
