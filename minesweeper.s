; VIA Port Definitions
PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
PCR   = $600c  ; Peripheral control register
IFR   = $600d  ; Interrupt flag register
IER   = $600e  ; Interrupt enable register

; LCD Control Bits
E  = %10000000  ; Enable bit
RW = %01000000  ; Read/Write bit
RS = %00100000  ; Register Select bit

; Button Input Masks (Port A)
LEFT  = %00001110
RIGHT = %00001101
UP    = %00001011
DOWN  = %00000111

; Interrupt Flags
MOVE_INT   = %00000010  ; Movement interrupt flag
SELECT_INT = %00010000  ; Selection interrupt flag

; Memory Layout (Page 2 and 3)
mine_array      = $0200  ; 8 bytes - Mine positions ($0200-$0207)
revealed_array  = $0208  ; 8 bytes - Revealed cells ($0208-$020F)
cursor_x        = $0210  ; 1 byte - Current cursor X position
cursor_y        = $0211  ; 1 byte - Current cursor Y position
bitmask         = $0212  ; 1 byte - Working bitmask
loc_mine_count  = $0213  ; 1 byte - Local mine counter
mine_count      = $0214  ; 1 byte - Total number of mines
cells_revealed  = $0215  ; 1 byte - Number of revealed cells
buff_ptr        = $0216  ; 1 byte - Display buffer pointer
temp            = $0217  ; 1 byte - Temporary storage
neighbor_x      = $0218  ; 1 byte - Neighbor X coordinate
neighbor_y      = $0219  ; 1 byte - Neighbor Y coordinate
neighbor_ptr    = $021A  ; 1 byte - Neighbor loop counter
blink_counter   = $021B  ; 1 byte - Counter for cursor blink
display_buffer  = $0300  ; 64 bytes for display ($0300-$033F)
number_array    = $0340  ; 64 bytes for mine numbers ($0340-$037F)

; Program Start
  .org $8000

; Game Data
win_message: .asciiz "You Won!"
lose_message: .asciiz "You Lost."

; ====================================
; Initialization
; ====================================
reset:
  sei                     ; Disable interrupts during init
  ldx #$ff
  txs                     ; Initialize stack pointer

  ; Initialize VIA
  lda #%00000000         ; Set interrupts to falling edge
  sta PCR
  lda #%10010010         ; Enable CA1 and CB1 interrupts
  sta IER

  ; Set up I/O ports
  lda #%11111111         ; PORTB: all output
  sta DDRB
  lda #%11100000         ; PORTA: top 3 pins output
  sta DDRA

  ; Initialize LCD
  lda #%00111000         ; 8-bit mode, 2-line display, 5x8 font
  jsr execute_lcd_instruction
  lda #%00001100         ; Display on, cursor off
  jsr execute_lcd_instruction
  lda #%00000110         ; Increment cursor, don't shift display
  jsr execute_lcd_instruction
  lda #$00000001         ; Clear display
  jsr execute_lcd_instruction

  ; Initialize game state
  lda #0
  sta cursor_x
  sta cursor_y
  sta cells_revealed
  sta blink_counter

  ; Clear arrays
  ldx #0
mine_setup:
  lda #0
  sta mine_array, x
  sta revealed_array, x
  sta number_array, x
  inx
  cpx #8
  bne mine_setup

  ; Initialize remaining number array
  ldx #8
continue_number_init:
  lda #0
  sta number_array, x
  inx
  cpx #64
  bne continue_number_init

  ; Set up initial mine positions
  lda #10
  sta mine_count
  
  lda #%01010000
  sta mine_array
  sta mine_array + 6
  lda #%00001000
  sta mine_array + 2
  sta mine_array + 3
  lda #%00000011
  sta mine_array + 4
  lda #%10000001
  sta mine_array + 7

; ====================================
; Main Game Loop
; ====================================
game_loop:
  ; Check win condition
  lda #64
  sec
  sbc mine_count
  cmp cells_revealed
  beq won

  inc blink_counter

  jsr update_display_buffer
  jsr update_display

  jmp game_loop

; ====================================
; Game End States
; ====================================
won:
  ldx #0
  lda #%00000001         ; Clear display
  jsr execute_lcd_instruction
won_loop:
  lda win_message, x
  beq done
  jsr print_char
  inx
  jmp won_loop

lost:
  ldx #0
  lda #%00000001         ; Clear display
  jsr execute_lcd_instruction
lost_loop:
  lda lose_message, x
  beq done
  jsr print_char
  inx
  jmp lost_loop

done:
  jmp done

; ====================================
; Display Update Routines
; ====================================

update_display:
  lda cursor_y           ; Determine which section to display
  lsr                    ; Divide by 2 to get section index (0-3)
  tax
  lda section_offsets,x  ; Load the corresponding offset
  tax                    ; Put offset in X for show routine
  jmp show              ; Continue with show routine
show:
  lda #%00000010         ; Return cursor home
  jsr execute_lcd_instruction

  ldy #0
show_loop:               ; Display first line
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #8
  beq print_page
  jmp show_loop

section_offsets: .byte 0, 16, 32, 48

print_page:              ; Add section number
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
  lda #"1"              ; Default to 1

newline:
  jsr print_char
  lda #%11000000        ; Move to second line
  jsr execute_lcd_instruction

show_loop2:             ; Display second line
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #16
  bne show_loop2
  rts

; ====================================
; Display Buffer Update
; ====================================
update_display_buffer:
  sei ;                   ; Protect shared data
  lda #0
  sta buff_ptr

  ldy #0                ; Row counter
row_loop:
  ldx #0                ; Column counter
col_loop:
  ; Calculate buffer position (y * 8) + x
  tya
  asl
  asl
  asl                   ; y * 8
  stx temp
  clc
  adc temp
  sta buff_ptr
  
  ; Check cursor position
  cpx cursor_x
  bne not_cursor
  cpy cursor_y
  bne not_cursor

  ; Blink logic
  lda blink_counter
  and #%01000000 ; toggles every 64 game cycles
  bne not_cursor
  
  ldx buff_ptr
  lda #"X"             ; Draw cursor
  sta display_buffer, x
  jmp next_col

not_cursor:
  ; Calculate bit position (7 - x)
  txa
  eor #7
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
  lda revealed_array, y
  and bitmask
  beq draw_hidden
  
  ; Show revealed number
  lda number_array, x
  clc
  adc #"0"             ; Convert to ASCII
  sta display_buffer, x
  jmp next_col

draw_hidden:
  lda #"."             ; Show hidden cell
  sta display_buffer, x

next_col:
  ldx temp             ; Restore x coordinate
  inx
  cpx #8
  bne col_loop

  iny
  cpy #8
  bne row_loop

  cli ;
  rts

; ====================================
; Neighbor Counting
; ====================================
neighbor_x_offset: .byte $ff, $00, $01, $ff, $01, $ff, $00, $01
neighbor_y_offset: .byte $ff, $ff, $ff, $00, $00, $01, $01, $01

count_neighbors:
  lda #0
  sta loc_mine_count
  sta neighbor_ptr

neighbor_loop:
  ldx neighbor_ptr
  cpx #8
  beq done_counting

; Calculate and validate neighbor X
  lda cursor_x
  clc                    
  adc neighbor_x_offset, x
  bmi skip_neighbor      ; Branch if negative
  cmp #8
  bcs skip_neighbor      ; Branch if >= 8
  sta neighbor_x

; Calculate and validate neighbor Y
  lda cursor_y
  clc
  adc neighbor_y_offset, x
  bmi skip_neighbor      ; Branch if negative
  cmp #8
  bcs skip_neighbor      ; Branch if >= 8
  sta neighbor_y

  ; Create bitmask for neighbor
  lda neighbor_x
  eor #7
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
  lda mine_array, x
  and bitmask
  beq skip_neighbor
  inc loc_mine_count

skip_neighbor:
  inc neighbor_ptr
  jmp neighbor_loop

done_counting:
  rts

; ====================================
; LCD Control Routines
; ====================================
lcd_wait:
  pha
  lda #%00000000         ; Set PORTB to input
  sta DDRB
lcdbusy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000         ; Check busy flag
  bne lcdbusy

  lda #RW
  sta PORTA
  lda #%11111111         ; Restore PORTB to output
  sta DDRB
  pla
  rts

execute_lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0                 ; Clear RS/RW/E
  sta PORTA
  lda #E                 ; Pulse E
  sta PORTA
  lda #0
  sta PORTA
  rts

print_char:
  jsr lcd_wait
  sta PORTB
  lda #RS                ; Set RS for character
  sta PORTA
  lda #(RS | E)         ; Pulse E
  sta PORTA
  lda #RS
  sta PORTA
  rts

; ====================================
; Interrupt Handler
; ====================================
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
  sta IFR                ; Clear interrupt flag
  
  ; Create bitmask for cursor position
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
  lda bitmask
  pha                    ; Save bitmask

  ; Check if already revealed
  ldx cursor_y
  lda revealed_array, x
  and bitmask
  beq not_revealed
  pla                    ; Clean up stack
  jmp exit_irq

not_revealed:
  ; Check for mine
  lda mine_array, x
  and bitmask
  beq not_mine
  pla
  jmp lost

not_mine:
  ; Calculate buffer position
  lda cursor_y
  asl
  asl
  asl
  clc
  adc cursor_x
  sta buff_ptr

  jsr count_neighbors

  ; Store number
  ldx buff_ptr
  lda loc_mine_count
  sta number_array, x

  ; Mark as revealed
  pla
  ldx cursor_y
  ora revealed_array, x
  sta revealed_array, x
  inc cells_revealed
  jmp exit_irq

move:
  lda #MOVE_INT
  sta IFR
  
  lda PORTA             ; Get button state
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
  jmp exit_irq

exit_irq:
  pla
  tax
  pla
  rti

; ====================================
; Interrupt Vectors
; ====================================
  .org $fffc
  .word reset
  .word irq
