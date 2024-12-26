PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

E  = %10000000
RW = %01000000
RS = %00100000

working_quotient = $0200 ; 2 bytes
mod10 = $0202 ; 2 bytes
prev_fibnum = $0204 ; 2 bytes
fibnum = $0206 ; 2 bytes
string = $0208 ; 6 bytes

  .org $8000

reset:
  ldx #$ff
  txs

  lda #%11111111 ; Set all pins on port B to output
  sta DDRB
  lda #%11100000 ; Set top 3 pins on port A to output
  sta DDRA

  lda #%00111000 ; Set 8-bit mode; 2-line display; 5x8 font
  jsr execute_lcd_instruction
  lda #%00001110 ; Display on; cursor on; blink off
  jsr execute_lcd_instruction
  lda #%00000110 ; Increment and shift cursor; don't shift display
  jsr execute_lcd_instruction

  lda #0 ; Initialize prev_fibnum to 0 and fibnum to 1
  sta prev_fibnum
  sta prev_fibnum + 1
  sta fibnum + 1
  lda #1
  sta fibnum

fib_loop:
  ldx #$ff
wait_loopx:
  ldy #$ff
wait_loopy:
  nop
  nop
  nop
  nop
  nop
  dey
  bne wait_loopy
  dex
  bne wait_loopx

  clc
  lda prev_fibnum
  adc fibnum 
  pha
  lda prev_fibnum + 1
  adc fibnum + 1
  pha ; Put the sum of prev_fibnum and fibnum on stack (most significant on top)
  lda fibnum
  sta prev_fibnum
  lda fibnum + 1
  sta prev_fibnum  + 1; Make prev_fibnum = fibnum
  pla
  sta fibnum + 1
  pla
  sta fibnum ; Make fibnum = sum
  
  jsr clear_string

  ; Initialize value to be the number to convert
  lda fibnum
  sta working_quotient
  lda fibnum + 1
  sta working_quotient + 1

divide:
  ; Initialize the remainder to zero
  lda #0
  sta mod10
  sta mod10 + 1
  clc
  ldx #16
divide_loop:
  ; Rotate quotient and remainder
  rol working_quotient
  rol working_quotient + 1
  rol mod10
  rol mod10 + 1
  ; a,y = dividend - devisor
  sec
  lda mod10
  sbc #10
  tay ; save low byte in Y
  lda mod10+1
  sbc #0
  bcc divide_ignore ; branch if dividend < devisor
  sty mod10
  sta mod10 + 1
divide_ignore:
  dex
  bne divide_loop
  rol working_quotient ; shift in the last bit of the quotient
  rol working_quotient + 1
  lda mod10
  clc
  adc #"0"
  jsr push_char
  ; if value != 0, then continue dividing
  lda working_quotient
  ora working_quotient + 1
  bne divide ; branch if value not equal to 0

  lda #%00000001 ; Clear display
  jsr execute_lcd_instruction

  ldx #0
print:
  lda string,x
  beq restart
  jsr lcd_wait
  sta PORTB
  lda #RS         ; Set RS; Clear RW/E bits
  sta PORTA
  lda #(RS | E)   ; Set E bit to send instruction
  sta PORTA
  lda #RS         ; Clear E bits
  sta PORTA
  inx
  jmp print
restart:
  jmp fib_loop

; SUBROUTINES

; makes string[0..5] = 0
clear_string:
  ldx #0
  lda #0
clear_string_loop:
  sta string,x
  inx
  cpx #6
  beq clear_string_break
  jmp clear_string_loop
clear_string_break:
  rts

; Add the character in the A register to the beginning of the 
; null-terminated string `string`
push_char:
  pha ; Push new first char onto stack
  ldy #0
push_char_loop:
  lda string,y ; Get char on the string and put into X
  tax
  pla
  sta string,y ; Pull char off stack and add it to the string
  iny
  txa
  pha           ; Push char from string onto stack
  bne push_char_loop
  pla
  sta string,y ; Pull the null off the stack and add to the end of the string
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

  .org $fffc
  .word reset
  .word $0000
