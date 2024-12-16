PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003

working_quotient = $0200 ; 2 bytes
mod10 = $0202 ; 2 bytes
prev  = $0204 ; 2 bytes
number = $0206 ; 2 bytes
number_string = $0208 ; 6 bytes

E  = %10000000 ; enable
RW = %01000000 ; read/write (write is active low)
RS = %00100000 ; register select (high is writing data, low is instruction)

  .org $8000

reset:
  ; reset stack pointer
  ldx #$ff
  txs

  ; set port b to output
  lda #%11111111
  sta DDRB
  ; set first 3 bits of a to output
  lda #%11100000
  sta DDRA

  lda #%00111000 ; 8 bit mode; 2 line display; 5x8 font
  jsr execute_lcd_instruction
  lda #%00001110 ; display and cursor on; blink off
  jsr execute_lcd_instruction
  lda #%00000110 ; increment and shift cursor; dont shift display
  jsr execute_lcd_instruction

  ; init fib_loop
  lda #0
  sta prev
  sta prev + 1
  sta number
  lda #1
  sta number + 1


fib_loop:
  ; add prev + number
  clc
  lda prev
  adc number
  sta working_quotient ; use working_quotient to store prev+number
  lda prev + 1
  adc number + 1
  sta working_quotient + 1
  ; make prev = number
  lda number
  sta prev
  lda number + 1
  sta prev + 1
  ; make number = sum (working_quotient)
  lda working_quotient
  sta number
  lda working_quotient + 1
  sta number + 1

  ; init working_quotient to be the number to convert to base 10
  lda number
  sta working_quotient
  lda number + 1
  sta working_quotient + 1
  
divide:
  ; init remainder to be 0
  lda #0
  sta mod10
  sta mod10 + 1
  clc

  ldx #16
divide_loop:
  rol working_quotient
  rol working_quotient + 1
  rol mod10
  rol mod10 + 1

  ; a,y = dividend 0 divisor
  sec
  lda mod10
  tay ; low byte into y
  lda mod10 + 1
  sbc #0
  bcc divide_ignore ; branch if dividend < divisor
  sty mod10
  sta mod10 + 1
divide_ignore:
  dex
  bne divide_loop
  rol working_quotient ; shift last bit of quotient
  rol working_quotient + 1

  jsr push_char

  ; if working_quotient != 0, continue
  lda working_quotient
  ora working_quotient + 1
  bne divide
  
  lda #%00000001
  jsr execute_lcd_instruction ; clear screen
  ldx #0
print_loop:
  ; set up loop and load character
  lda number_string,x
  beq fib_loop
  ; wait and then write character
  jsr lcd_wait
  sta PORTB
  lda RS
  sta PORTA
  lda #(RS | E)
  sta PORTA
  lda RS
  ; increment and loop
  inx
  jmp print_loop


execute_lcd_instruction:
  jsr lcd_wait ; wait for lcd to finish previous instruction

  sta PORTB ; set instruction

  ; clear E/RW/RS bits
  lda #0
  sta PORTA
  ; flash enable signal
  lda E
  sta PORTA
  lda #0
  sta PORTA
  rts


lcd_wait:
  pha
  lda #0 ; set port b to input
  sta DDRB
lcd_wait_loop:
  ; read busy signal and load into a register
  lda RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB

  ; if busy bit is high, loop
  and #%10000000
  bne lcd_wait_loop

  ; reset and return
  lda RW
  sta PORTA
  lda #%11111111
  sta DDRB
  pla
  rts


push_char:
  ldx #5 ; start at end of number_string
push_char_loop:
  lda number_string,x
  sta number_string + 1, x
  dex
  bpl push_char_loop ; shift all elements to the right

  clc
  lda mod10
  adc #"0"
  sta number_string ; add new char at beginning
  rts

  .org $fffc
  .word reset
  .word $0000
