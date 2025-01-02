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
loc_mine_count = $0213 ; 1 byte

game_state = $0214 ; 1 byte
mine_count = $0215 ; 1 byte
cells_revealed = $0216 ; 1 byte
buff_ptr = $0217 ; 1 byte
temp = $0218 ; 1 byte
display_buffer = $0219 ; 64 bytes
number_array = $0259 ; 64 bytes for storing pre-calculated numbers

neighbor_x = $021A ; 1 byte Temporary storage for neighbor x coordinate
neighbor_y = $021B ; 1 byte Temporary storage for neighbor y coordinate
neighbor_ptr = $021C ; 1 bytePointer for neighbor loop
  
GAME_ACTIVE = %10000000

  .org $8000

win_message: .asciiz "You Won!"
lose_message: .asciiz "You Lost."

reset:
  sei

  ldx #$ff
  txs

  lda #%00000000 ; Set interupts to happen on falling edge
  sta PCR
  lda #%10010010 ; Enable CA1 and CB1 interrupts
  sta IER

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
  sta number_array, x   ; Initialize number array
  inx
  cpx #8
  bne mine_setup

  ; Initialize rest of number array
  ldx #8
continue_number_init:
  lda #0
  sta number_array, x
  inx
  cpx #64
  bne continue_number_init

  lda #56
  sta mine_count
  
  lda #%11111111
  sta mine_array
  sta mine_array + 1
  sta mine_array + 2
  sta mine_array + 3
  sta mine_array + 4
  sta mine_array + 5
  sta mine_array + 6

  ldx #0
buffer_setup:
  lda #" "
  sta display_buffer, x
  inx
  cpx #64
  bne buffer_setup
  cli

game_loop:
  lda game_state
  and #GAME_ACTIVE
  beq lost

  lda #64
  sec
  sbc mine_count
  sta temp
  lda cells_revealed
  cmp temp
  beq won

  jsr update_display_buffer
  jsr update_display

  jmp game_loop

won:
  ldx #0
  lda #%00000001 ; clear display
  jsr execute_lcd_instruction
won_loop:
  lda win_message, x
  beq done
  jsr print_char
  inx
  jmp won_loop

lost:
  ldx #0
  lda #%00000001 ; clear display
  jsr execute_lcd_instruction
lost_loop:
  lda lose_message, x
  beq done
  jsr print_char
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
  lda #%00000010 ; Clear display
  jsr execute_lcd_instruction

  ldy #0
show_loop:
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #8
  beq print_page
  jmp show_loop
print_page:
  lda #" "
  jsr print_char
  jsr print_char
  jsr print_char
  jsr print_char
  lda #"4"
  cpx #56
  beq newline
  lda #"3"
  cpx #40
  beq newline
  lda #"2"
  cpx #24
  beq newline
  lda #"1" ; default to 1
newline:
  jsr print_char
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
  sei                   ; Since we're touching shared data
  lda #0
  sta buff_ptr          ; clear buffer pointer
  
  ldy #0                ; y coordinate counter
row_loop:
  ldx #0                ; x coordinate counter
col_loop:
  ; Calculate buffer position (y * 8) + x
  tya
  asl
  asl
  asl                   ; y * 8
  stx temp
  clc
  adc temp              ; add x
  sta buff_ptr
  
  ; Check if this is cursor position
  cpx cursor_x
  bne not_cursor
  cpy cursor_y
  bne not_cursor
  
  ; Draw cursor on revealed space
  ldx buff_ptr
  lda #"X"
  sta display_buffer, x
  jmp next_col
not_cursor:
  ; Calculate bit position (7 - x)
  txa
  eor #7                ; flip bits to get 7-x
  tax
  lda #1
  sta bitmask
shift_bitmask1:
  cpx #0
  beq check_revealed
  asl bitmask
  dex
  jmp shift_bitmask1
check_revealed:
  ldx buff_ptr          
  lda revealed_array, y ; get revealed status for this row
  and bitmask
  beq draw_hidden       ; if not revealed, show hidden
  
  ; Display the pre-calculated number
  lda number_array, x
  clc
  adc #"0"             ; convert to ASCII
  sta display_buffer, x
  jmp next_col
draw_hidden:
  lda #"."             ; or whatever character for hidden
  sta display_buffer, x
next_col:
  ldx temp             ; restore x coordinate
  inx
  cpx #8
  beq next_row
  jmp col_loop
next_row:
  iny
  cpy #8
  beq done_update
  jmp row_loop
done_update:
  cli                   ; Make sure interrupts are enabled before returning
  rts

neighbor_x_offset: .byte $ff, $00, $01, $ff, $01, $ff, $00, $01 ; -1, 0, 1, -1, 1, -1, 0, 1
neighbor_y_offset: .byte $ff, $ff, $ff, $00, $00, $01, $01, $01 ; -1,-1,-1, 0, 0, 1, 1, 1

count_neighbors:
  lda #0
  sta loc_mine_count   ; Initialize mine count to 0
  sta neighbor_ptr     ; Initialize neighbor pointer

neighbor_loop:
  ldx neighbor_ptr
  cpx #8              ; Check if we've processed all 8 neighbors
  beq done_counting

; Calculate neighbor X coordinate
  lda cursor_x
  clc                    
  adc neighbor_x_offset, x  
  bpl check_x_upper     ; If result is positive, check upper bound
  ; If negative result, skip this neighbor
  jmp skip_neighbor
check_x_upper:
  cmp #8
  bpl skip_neighbor

  sta neighbor_x        ; Store valid X coordinate
  
  ; Calculate neighbor Y coordinate - same logic
  lda cursor_y
  clc
  adc neighbor_y_offset, x
  bpl check_y_upper
  jmp skip_neighbor
check_y_upper:
  cmp #8
  bpl skip_neighbor
  
  sta neighbor_y        ; Store valid Y coordinate
  ; Create bitmask for neighbor position
  lda neighbor_x
  eor #7              ; Flip bits to get 7-x
  tax
  lda #1
  sta bitmask

shift_neighbor_mask:
  cpx #0
  beq check_mine
  asl bitmask
  dex
  jmp shift_neighbor_mask

check_mine:
  ldx neighbor_y
  lda mine_array, x    ; Get mine status for this row
  and bitmask         ; Check if mine exists at this position
  beq skip_neighbor
  inc loc_mine_count   ; Increment count if mine found

skip_neighbor:
  inc neighbor_ptr
  jmp neighbor_loop

done_counting:
  rts

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
  and #SELECT_INT
  bne select
  lda IFR
  and #MOVE_INT
  bne move
  jmp exit_irq

select:
  lda #SELECT_INT 
  sta IFR           

  lda PORTB
  
  ; create bitmask of x'th bit (7-x to flip bit order)
  lda cursor_x
  eor #7
  tax
  lda #1
  sta bitmask
shift_bitmask3:
  cpx #0
  beq check_mine_hit
  asl bitmask
  dex
  jmp shift_bitmask3

check_mine_hit:
  ; Save this bitmask for later
  lda bitmask
  pha               ; Save the cursor's bitmask

  ; Don't modify any already-revealed cells
  ldx cursor_y
  lda revealed_array, x
  and bitmask
  beq not_revealed
  pla               ; Clean up stack
  jmp exit_irq
not_revealed:
  ; Check for mine
  lda mine_array, x
  and bitmask      ; Using cursor's bitmask to check for mine
  bne mine_hit

  ; Calculate buffer position using same method as display
  lda cursor_y
  asl
  asl
  asl                  ; y * 8
  clc
  adc cursor_x         ; add x
  sta buff_ptr         ; Use same buff_ptr as display routine

  ; Count neighboring mines
  jsr count_neighbors

  ; Store counted number in correct position
  ldx buff_ptr
  lda loc_mine_count   ; Use the counted value instead of hardcoded 1
  sta number_array, x   

  ; add to revealed_array using the saved cursor bitmask
  pla                  ; Restore the cursor's bitmask
  ldx cursor_y
  ora revealed_array, x ; OR with existing revealed bits
  sta revealed_array, x
  inc cells_revealed
  jmp exit_irq

mine_hit:
  pla                  ; Clean up stack
  lda #%00000000
  sta game_state
  jmp exit_irq


move:
  lda #MOVE_INT      ; Clear the CA1 interrupt flag
  sta IFR
  
  lda PORTA          ; Read the button state from PORTA
  and #%00001111     ; Mask to just get the button bits
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
  jmp exit_irq

exit_irq:
  pla
  tax
  pla
  rti

  .org $fffc
  .word reset
  .word irq
