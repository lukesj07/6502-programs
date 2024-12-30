PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

E  = %10000000
RW = %01000000
RS = %00100000

working_quotient = $0200 ; 4 bytes
mod10 = $0204 ; 4 bytes
prev_fibnum = $0208 ; 4 bytes
fibnum = $020c ; 4 bytes
string = $0210 ; 11 bytes

  .org $8000

done:
  jmp done
  
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
  lda #%00000110 ; Increment and shift cursor; don't shift display (dont know if this is right or needed)
  jsr execute_lcd_instruction
  lda #%00000001 ; Clear display
  jsr execute_lcd_instruction

  lda #0 ; Initialize prev_fibnum to 0 and fibnum to 1
  sta prev_fibnum
  sta prev_fibnum + 1
  sta prev_fibnum + 2
  sta prev_fibnum + 3
  sta fibnum + 1
  sta fibnum + 2
  sta fibnum + 3
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
  nop
  dey
  bne wait_loopy
  dex
  bne wait_loopx

  clc ; make more memory efficient with loop using xth byte?
  lda prev_fibnum
  adc fibnum
  pha
  lda prev_fibnum + 1
  adc fibnum + 1
  pha
  lda prev_fibnum + 2
  adc fibnum + 2
  pha
  lda prev_fibnum + 3
  adc fibnum + 3
  pha ; Put the sum of prev_fibnum and fibnum on stack (most significant on top)
  bcs done ; Break if overflow is detected

  lda fibnum
  sta prev_fibnum
  lda fibnum + 1
  sta prev_fibnum  + 1
  lda fibnum + 2
  sta prev_fibnum + 2
  lda fibnum + 3
  sta prev_fibnum + 3 ; Make prev_fibnum = fibnum
  pla
  sta fibnum + 3
  pla
  sta fibnum + 2
  pla
  sta fibnum + 1
  pla
  sta fibnum ; Make fibnum = sum
  
  lda #0
  sta string ; replacement for clear_string sr

  ; Initialize value to be the number to convert
  lda fibnum
  sta working_quotient
  lda fibnum + 1
  sta working_quotient + 1
  lda fibnum + 2
  sta working_quotient + 2
  lda fibnum + 3
  sta working_quotient + 3

divide:
  ; Initialize the remainder to zero
  lda #0
  sta mod10
  sta mod10 + 1
  sta mod10 + 2
  sta mod10 + 3
  clc
  ldx #32
divide_loop:
  ; Rotate quotient and remainder
  rol working_quotient
  rol working_quotient + 1
  rol working_quotient + 2
  rol working_quotient + 3
  rol mod10
  rol mod10 + 1
  rol mod10 + 2
  rol mod10 + 3
  ; dividend - divisor
  sec
  lda mod10
  sbc #10
  pha
  lda mod10 + 1
  sbc #0
  pha ; keep result stored in the stack
  lda mod10 + 2
  sbc #0
  pha
  lda mod10 + 3
  sbc #0
  bcc divide_ignore_pull ; branch if dividend < devisor
  sta mod10 + 3
  pla
  sta mod10 + 2
  pla
  sta mod10 + 1
  pla
  sta mod10
  jmp divide_ignore
divide_ignore_pull: ; Pulls extra info off stack when needed
  pla
  pla
  pla
divide_ignore:
  dex
  bne divide_loop
  rol working_quotient ; shift in the last bit of the quotient
  rol working_quotient + 1
  rol working_quotient + 2
  rol working_quotient + 3
  lda mod10
  clc
  adc #"0"
  jsr push_char
  ; if value != 0, then continue dividing
  lda working_quotient
  ora working_quotient + 1
  ora working_quotient + 2
  ora working_quotient + 3
  bne divide ; branch if value not equal to 0

  lda #%00000010 ; Home (faster than clearing)
  jsr execute_lcd_instruction

  ldx #0
print:
  lda string,x
  beq next_num
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
next_num:
  jmp fib_loop

; SUBROUTINES

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
