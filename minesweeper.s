PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
PCR   = $600c ; Peripheral control
IFR   = $600d ; Interrupt flag
IER   = $600e ; Interrupt enable

E  = %10000000
RW = %01000000
RS = %00100000

LEFT  = %00001110 ; from port a 
RIGHT = %00001101
UP    = %00001011
DOWN  = %00000111

MOVE_INT   = %00000010 ; in IFR
SELECT_INT = %00010000

mine_array = $0200 ; 8 bytes
revealed_array = $0208 ; 8 bytes
cursor_x = $0210 ; 1 byte
cursor_y = $0211 ; 1 byte

bitmask = $0212 ; 1 byte
loc_mine_count = $0213

game_state = $0214 ; 1 byte
mine_count = $0215 ; 1 byte
cells_revealed = $0216 ; 1 byte
buff_ptr = $0217 ; 1 byte
temp = $0218 ; 1 byte
display_buffer = $0219 ; 64 bytes

GAME_ACTIVE = %10000000

  .org $8000

win_message: .asciiz "You Won!"
lose_message: .asciiz "You Lost."

neighbor_offsetsx:
  .byte -1, 0, 1
  .byte -1,    1
  .byte -1, 0, 1

neighbor_offsetsy:
  .byte -1, -1, -1
  .byte  0,      0
  .byte  1,  1,  1

reset:
  ldx #$ff
  txs

  lda #%00000000 ; Set interupts to happen on falling edge
  sta PCR
  lda #%10010010 ; Enable CA1 and CB1 interrupts
  sta IER
  cli

  lda #%11111111 ; Set all pins of PORTB to output
  sta DDRB
  lda #%11100000 ; Top 3 pins of PORTA to output
  sta DDRA


  lda #%00111000 ; 8-bit mode, 2-line display, 5x8 font 
  jsr execute_lcd_instruction
  lda #%00001100 ; Display on, cursor off
  jsr execute_lcd_instruction
  lda #%00000110 ; Increment and shift cursor, dont shift display
  jsr execute_lcd_instruction
  lda #$00000001 ; Clear Display
  jsr execute_lcd_instruction

  ; INITIALIZE VARS
  lda #0
  sta cursor_x
  sta cursor_y
  sta cells_revealed
  lda #%10000000
  sta game_state

  ldx #0
mine_setup:
  lda #0
  sta mine_array, x
  sta revealed_array, x
  inx
  cpx #8
  bne mine_setup

  lda #3
  sta mine_count
  
  lda #%10000000
  sta mine_array
  sta mine_array + 1
  sta mine_array + 2

  ldx #0
buffer_setup:
  lda #" "
  sta display_buffer, x
  inx
  cpx #64
  bne buffer_setup

game_loop:
  lda game_state
  and #%10000000
  beq lost

  lda #64
  clc
  sbc mine_count
  sta temp
  lda cells_revealed
  clc
  sbc temp
  beq won

  ;jsr update_display_buffer
  jsr update_display

  jmp game_loop

won:
  ldx #0
  lda #%00000001 ; clear display
  jsr execute_lcd_instruction
won_loop:
  lda win_message, x
  beq done
  inx
  jmp won_loop
lost:
  ldx #0
  lda #%00000001 ; clear display
  jsr execute_lcd_instruction
lost_loop:
  lda lose_message, x
  beq done
  inx
  jmp lost_loop

done:
  jmp done


update_display:
  lda cursor_y
  cmp #2
  bmi section_1
  cmp #4
  bmi section_2
  cmp #6
  bmi section_3
  ; section 4
  ldx #48
  jmp show
section_1:
  ldx #0
  jmp show
section_2:
  ldx #16
  jmp show
section_3:
  ldx #32
  jmp show
show:
  lda #%00000001 ; Clear display
  jsr execute_lcd_instruction

  ldy #0
show_loop:
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #8
  beq newline
  jmp show_loop
newline:
  lda #%11000000 ; Start at beginning of 2nd line
  jsr execute_lcd_instruction
show_loop2:
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #16
  bne show_loop2
  rts


update_display_buffer:
  sei
  ldy #0
  sty buff_ptr
row_update_loop:
  tya
  asl
  asl
  asl ; multiply curr y by 8 to get byte at beginning of row

  ldx #0
col_update_loop:
  clc
  stx temp
  adc temp ; update buff_ptr
  sta buff_ptr

; check cursor position

  lda cursor_x
  sta temp
  cpx temp
  bne no_cursor
  
  lda cursor_y
  sta temp
  cpy temp
  bne no_cursor

  txa
  pha ; push x to stack

  ldx buff_ptr
  lda #"X"
  sta display_buffer, x
  
  pla
  tax ; take x off stack
  jmp next_space

no_cursor:
  txa
  pha ; put x on stack
  
  clc
  lda #7
  stx temp
  sbc temp
  tax
  lda #1
  sta bitmask
  asl bitmask, x ; create bitmask for current bit in byte of revealed_array

  pla
  tax ; take x off stack

  lda revealed_array, y
  and bitmask
  bne print_revealed
  jmp next_space
print_revealed:
  lda #0
  sta loc_mine_count

  tya
  pha ; push y to stack
  txa
  pha ; push x to stack

  ldx #0
neighbor_check:
  stx temp
  pla
  tax ; put index x in temp and mine x in x
  lda temp
  pha ; put index x on stack
  txa
  pha ; push mine x twice because it gets pulled without being repushed
  pha

  ldx temp

  lda neighbor_offsetsy, x
  clc
  sty temp
  adc temp
  tay ; put y coord of neighbor in y register
  pla
  clc
  adc neighbor_offsetsx, x
  tax ; put x coord of neighbor in x register

  cpx #0
  bmi next_neighbor
  cpx #7
  bpl next_neighbor
  cpy #0
  bmi next_neighbor
  cpy #7
  bpl next_neighbor

  clc
  lda #7
  stx temp
  sbc temp
  tax
  lda #1
  sta bitmask
  asl bitmask, x ; make neighbor bitmask

  pla
  sta temp
  pla
  tax
  lda temp
  pha

  lda mine_array, y
  and bitmask
  beq next_neighbor
  inc loc_mine_count
next_neighbor:
  inx
  cpx #8
  bne neighbor_check

  ldx buff_ptr
  lda loc_mine_count
  clc
  adc #"0"
  sta display_buffer, x

  pla
  tax
  pla
  tay

next_space:
  inx
  cpx #8
  bne col_update_jump
  iny
  cpy #8
  bne row_update_jump
  cli
  rts
col_update_jump:
  jmp col_update_loop
row_update_jump:
  jmp row_update_loop


lcd_wait:
  pha
  lda #%00000000  ; Port B is input
  sta DDRB
lcdbusy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000
  bne lcdbusy

  lda #RW
  sta PORTA
  lda #%11111111  ; Port B is output
  sta DDRB
  pla
  rts

execute_lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  lda #E         ; Set E bit to send instruction
  sta PORTA
  lda #0         ; Clear RS/RW/E bits
  sta PORTA
  rts

print_char:
  jsr lcd_wait
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA
  rts



irq:
  pha
  txa
  pha
  lda IFR
  cmp SELECT_INT
  beq select
  cmp MOVE_INT
  beq move
  jmp exit_irq

select:
  bit PORTB ; clear interrupt, does this work since portb is output?

  ; create bitmask of x'th bit
  clc
  lda #7
  sbc cursor_x
  tax
  lda #1
  sta bitmask
  asl bitmask, x

  ; check if mine
  ldx cursor_y
  lda mine_array, x ; a is cursor_y'th byte
  and bitmask
  bne mine_hit

  ; add to revealed_array
  lda revealed_array, x
  ora bitmask
  sta revealed_array, x
  ldx cells_revealed
  inx
  stx cells_revealed
  jmp exit_irq

mine_hit:
  lda #%00000000
  sta game_state
  jmp exit_irq

move:
  lda PORTA ; get info and clear interrupt
  and #%00001111
  cmp #LEFT
  beq move_left
  cmp #RIGHT
  beq move_right
  cmp #UP
  beq move_up
  cmp #DOWN
  beq move_down
  jmp exit_irq
move_left:
  ldx cursor_x
  cpx #0
  beq exit_irq
  dex
  stx cursor_x
  jmp exit_irq
move_right:
  ldx cursor_x
  cpx #7
  beq exit_irq
  inx
  stx cursor_x
  jmp exit_irq
move_up:
  ldx cursor_y
  cpx #0
  beq exit_irq
  dex
  stx cursor_y
  jmp exit_irq
move_down:
  ldx cursor_y
  cpx #7
  beq exit_irq
  inx
  stx cursor_y
  jmp exit_irq ; may remove
exit_irq:
  pla
  tax
  pla
  rti

  .org $fffc
  .word reset
  .word irq
