; VIA ports
PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
PCR   = $600c  ; peripheral control register
IFR   = $600d  ; interrupt flag register
IER   = $600e  ; interrupt enable register

; LCD control bits
E  = %10000000  ; enable bit
RW = %01000000  ; read/write bit
RS = %00100000  ; register select bit

; button input masks (port a)
LEFT  = %00001110
RIGHT = %00001101
UP    = %00001011
DOWN  = %00000111

; interrupt flags
MOVE_INT   = %00000010  ; movement interrupt flag
SELECT_INT = %00010000  ; selection interrupt flag

; memory layout
; zero page variables (most used)
display_buffer  = $00  ; 64 bytes for display ($0300-$033F)
number_array    = $40  ; 64 bytes for mine numbers ($0340-$037F)
cursor_x        = $80  ; 1 byte - current cursor x
cursor_y        = $81  ; 1 byte - current cursor y
bitmask         = $82  ; 1 byte - working bitmask
buff_ptr        = $83  ; 1 byte - display buffer pointer
temp            = $84  ; 1 byte - temporary storage

; page 2 
mine_array      = $0200  ; 8 bytes - mine positions ($0200-$0207)
revealed_array  = $0208  ; 8 bytes - revealed cells ($0208-$020F)
loc_mine_count  = $0210  ; 1 byte - local mine counter
mine_count      = $0211  ; 1 byte - total number of mines
cells_revealed  = $0212  ; 1 byte - number of revealed cells
neighbor_x      = $0213  ; 1 byte - neighbor X coordinate
neighbor_y      = $0214  ; 1 byte - neighbor Y coordinate
neighbor_ptr    = $0215  ; 1 byte - neighbor loop counter
blink_counter   = $0216  ; 1 byte - counter for cursor blink
startup_timer   = $0217  ; 1 byte - timer used as a random seed for mine generation
game_started    = $0218  ; 1 byte - flag for game state

  .org $8000

win_message: .asciiz "You Won!"
lose_message: .asciiz "You Lost."
title_msg: .asciiz "MINESWEEPER"
press_msg: .asciiz "Press SELECT"

; ====================================
; Initialization
; ====================================
reset:
  sei                     ; disable interrupts during init
  ldx #$ff
  txs                     ; initialize stack pointer

  ; initialize VIA
  lda #%00000000         ; set interrupts to falling edge
  sta PCR
  lda #%10010010         ; enable CA1 and CB1 interrupts
  sta IER

  ; set up io ports
  lda #%11111111         ; PORTB: all output
  sta DDRB
  lda #%11100000         ; PORTA: top 3 pins output
  sta DDRA

  ; init LCD
  lda #%00111000         ; 8-bit mode, 2-line display, 5x8 font
  jsr execute_lcd_instruction
  lda #%00001100         ; display on, cursor off
  jsr execute_lcd_instruction
  lda #%00000110         ; increment cursor, don't shift display
  jsr execute_lcd_instruction
  lda #$00000001         ; clear display
  jsr execute_lcd_instruction

  ; init game state
  lda #0
  sta game_started       ; clear game started flag
  sta startup_timer      ; clear startup timer

  jsr show_title_screen  ; show title screen
  cli                    ; enable interrupts to detect SELECT
  jmp startup_loop       ; enter startup loop

; show title screen
show_title_screen:
  ; center "MINESWEEPER" on first line
  lda #%00000010         ; cursor home
  jsr execute_lcd_instruction
  lda #" "               ; 3 spaces for centering
  jsr print_char
  jsr print_char
  jsr print_char
  
  ldx #0
title_loop:
  lda title_msg, x
  beq title_done
  jsr print_char
  inx
  jmp title_loop
title_done:

  ; "Press SELECT" on second line
  lda #%11000000         ; move to second line
  jsr execute_lcd_instruction
  lda #" "               ; 2 spaces for centering
  jsr print_char
  jsr print_char
  
  ldx #0
press_loop:
  lda press_msg, x
  beq press_done
  jsr print_char
  inx
  jmp press_loop
press_done:
  rts

; startup loop with timer
startup_loop:
  inc startup_timer      ; increment timer
  
  ; check if SELECT was pressed (via interrupt)
  lda game_started
  beq startup_loop       ; If not started, continue loop

  sei                   ; disable interrupts during debounce delay and during generation

  ldx #$FF
outer_dbdelay:
  ldy #$FF
inner_dbdelay:
  dey
  bne inner_dbdelay
  dex
  bne outer_dbdelay
  
  ; start game setup
  jsr clear_board
  jsr place_mines
  jmp init_game


clear_board:
  ldx #0
clear_loop:
  lda #0
  sta mine_array, x
  sta revealed_array, x
  sta number_array, x
  inx
  cpx #8
  bne clear_loop
  
  ; clear remaining number array
  ldx #8
continue_number_clear:
  lda #0
  sta number_array, x
  inx
  cpx #64
  bne continue_number_clear
  rts

; generate a random number using timer value
get_random:
  lda startup_timer
  asl
  bcc no_eor
  eor #$1D
no_eor:
  sta startup_timer      ; store back the rotated value
  rts

; place mines randomly
place_mines:
  lda #0
  sta mine_count
place_loop:
  lda mine_count
  cmp #10                ; check if 10 mines have been placed
  beq mines_done
  
  jsr get_random         ; get random x position (0-7)
  and #%00000111
  tax                    ; use x register for x position
  
  jsr get_random         ; get random y position (0-7)
  and #%00000111
  tay                    ; use y register for y position
  
  jsr create_bitmask

check_position:
  tya                    ; get y position back for array index
  tax
  lda mine_array, x      ; check if position already has mine
  and bitmask
  bne place_loop         ; if mine exists, try again
  
  ; place mine
  lda mine_array, x
  ora bitmask
  sta mine_array, x
  inc mine_count
  jmp place_loop

mines_done:
  rts


init_game:
  lda #0
  sta cursor_x
  sta cursor_y
  sta cells_revealed
  sta blink_counter
  
  lda #%00000001         ; clear display before starting game
  jsr execute_lcd_instruction
  
  cli                    ; enable interrupts
; ====================================
; Main Game Loop
; ====================================
game_loop:
  ; check if won
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
  lda #%00000001         ; clear display
  jsr execute_lcd_instruction
won_loop:
  lda win_message, x
  beq done
  jsr print_char
  inx
  jmp won_loop

lost:
  ldx #0
  lda #%00000001         ; clear display
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
  lda cursor_y           ; determine which section to display
  lsr                    ; divide by 2 to get section index (0-3)
  tax
  lda section_offsets,x  ; load the corresponding offset
  tax                    ; put offset in x for show routine
  jmp show               ; continue with show routine
show:
  lda #%00000010         ; cursor home
  jsr execute_lcd_instruction

  ldy #0
show_loop:               ; display first line
  lda display_buffer, x
  jsr print_char
  inx
  iny
  cpy #8
  beq print_page
  jmp show_loop

section_offsets: .byte 0, 16, 32, 48

print_page:              ; add section number
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
  lda #"1"              ; default to 1

newline:
  jsr print_char
  lda #%11000000        ; move to second line
  jsr execute_lcd_instruction

show_loop2:             ; display second line
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
  sei ;                   ; protect shared data
  lda #0
  sta buff_ptr

  ldy #0                ; row counter
row_loop:
  ldx #0                ; column counter
col_loop:
  ; calculate buffer position (y * 8) + x
  tya
  asl
  asl
  asl                   ; y * 8
  stx temp
  clc
  adc temp
  sta buff_ptr
  
  ; check cursor position
  cpx cursor_x
  bne not_cursor
  cpy cursor_y
  bne not_cursor

  ; blink logic
  lda blink_counter
  and #%01000000 ; toggles every 64 game cycles
  bne not_cursor
  
  ldx buff_ptr
  lda #"X"             ; draw cursor
  sta display_buffer, x
  jmp next_col

not_cursor:
  jsr create_bitmask
  ; check if revealed
  ldx buff_ptr
  lda revealed_array, y
  and bitmask
  beq draw_hidden
  
  ; show revealed number
  lda number_array, x
  clc
  adc #"0"             ; convert to ascii
  sta display_buffer, x
  jmp next_col

draw_hidden:
  lda #"."             ; show hidden cell
  sta display_buffer, x

next_col:
  ldx temp             ; restore x coordinate
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

; calculate and validate neighbor x
  lda cursor_x
  clc                    
  adc neighbor_x_offset, x
  bmi skip_neighbor      ; branch if negative
  cmp #8
  bcs skip_neighbor      ; branch if >= 8
  sta neighbor_x

; calculate and validate neighbor y
  lda cursor_y
  clc
  adc neighbor_y_offset, x
  bmi skip_neighbor      ; branch if negative
  cmp #8
  bcs skip_neighbor      ; branch if >= 8
  sta neighbor_y

  ldx neighbor_x
  jsr create_bitmask

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
; Bitmask Creation
; ====================================
; input: X register contains position (0-7)
; output: bitmask variable contains shifted result
create_bitmask:
  txa           ; get position
  eor #7        ; flip 0-7 to 7-0
  tax
  lda #1        ; start with bit 0
  cpx #0
  beq shift_end
shift_loop:
  asl           ; shift left
  dex
  bne shift_loop
shift_end:
  sta bitmask
  rts

; ====================================
; LCD Control Routines
; ====================================
lcd_wait:
  pha
  lda #%00000000         ; set PORTB to input
  sta DDRB
lcdbusy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000         ; check busy flag
  bne lcdbusy

  lda #RW
  sta PORTA
  lda #%11111111         ; restore PORTB to output
  sta DDRB
  pla
  rts

execute_lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0                 ; clear RS/RW/E
  sta PORTA
  lda #E                 ; pulse E
  sta PORTA
  lda #0
  sta PORTA
  rts

print_char:
  jsr lcd_wait
  sta PORTB
  lda #RS                ; set RS for character
  sta PORTA
  lda #(RS | E)          ; pulse E
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
  sta IFR                ; clear interrupt flag
  
  lda game_started       ; check if game has started
  bne normal_select      ; if started, handle normally
  
  ; handle startup select
  lda #1
  sta game_started       ; set game started flag
  jmp exit_irq
  
normal_select:
  ; create bitmask for cursor position
  ldx cursor_x
  jsr create_bitmask

check_mine_hit:
  lda bitmask
  pha                    ; save bitmask

  ; check if already revealed
  ldx cursor_y
  lda revealed_array, x
  and bitmask
  beq not_revealed
  pla                    ; clean up stack
  jmp exit_irq

not_revealed:
  ; check for mine
  lda mine_array, x
  and bitmask
  beq not_mine
  pla
  jmp lost

not_mine:
  ; calculate buffer position
  lda cursor_y
  asl
  asl
  asl
  clc
  adc cursor_x
  sta buff_ptr

  jsr count_neighbors

  ; store number
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
  
  lda PORTA             ; get button state
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
