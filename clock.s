; VIA registers
PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
PCR   = $600c    ; Peripheral Control Register
IFR   = $600d    ; Interrupt Flag Register
IER   = $600e    ; Interrupt Enable Register

; LCD control bits
E  = %10000000
RW = %01000000
RS = %00100000

; Variables
time_h = $00
time_m = $01
time_s = $02
counter_low = $03  ; Low byte of counter
counter_high = $04 ; High byte of counter
temp   = $05      ; For BCD conversion

  .org $8000

reset:
  sei              ; Disable interrupts
  ldx #$ff
  txs              ; Initialize stack pointer
  
  ; Set up VIA
  lda #%11111111   ; PORTB = output
  sta DDRB
  lda #%11100000   ; PORTA = LCD control output
  sta DDRA
  
  ; Set up CB1 interrupt
  lda #%00000000   ; Set CB1 to interrupt on falling edge
  sta PCR
  lda #%10010000   ; Enable CB1 interrupts (bit 4)
  sta IER

  ; Set up LCD
  jsr lcd_wait
  lda #%00111000   ; 8-bit mode, 2-line
  jsr lcd_instruction
  lda #%00001100   ; Display on, cursor off
  jsr lcd_instruction
  lda #%00000110   ; Increment address
  jsr lcd_instruction
  lda #%00000001   ; Clear display
  jsr lcd_instruction

  ; Initialize time to 12:00:00
  lda #12
  sta time_h
  lda #0
  sta time_m
  sta time_s
  sta counter_low
  sta counter_high
  
  cli              ; Enable interrupts

main_loop:
  jsr update_time
  jsr display_time
  jmp main_loop

update_time:
  ; Increment 16-bit counter
  inc counter_low
  bne check_counter   ; If low byte didn't wrap, skip high byte
  inc counter_high    ; If low byte wrapped, increment high byte

check_counter:
  lda counter_high
  cmp #3             ; Check for 964 (3 * 256 + 196)
  bcc ut_done        ; If less than 3, not there yet
  bne reset_counter  ; If more than 3, we've passed
  lda counter_low
  cmp #196           ; Check low byte
  bcc ut_done

reset_counter:
  ; Reset counter to 0
  lda #0
  sta counter_low
  sta counter_high

  ; Update seconds
  inc time_s
  lda time_s
  cmp #60
  bne ut_done
  lda #0
  sta time_s

  ; Update minutes
  inc time_m
  jsr check_minute_rollover

ut_done:
  rts

; Handle minute increment and hour rollover
check_minute_rollover:
  lda time_m
  cmp #60
  bne mr_done
  lda #0
  sta time_m
  
  ; Update hours
  inc time_h
  lda time_h
  cmp #13
  bne mr_done
  lda #1
  sta time_h
mr_done:
  rts

display_time:
  lda #%10000000  ; First line
  jsr lcd_instruction
  
  ; Display hours
  lda time_h
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char
  
  ; Display :
  lda #":"
  jsr lcd_char
  
  ; Display minutes
  lda time_m
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char

  ; Display :
  lda #":"
  jsr lcd_char
  
  ; Display seconds
  lda time_s
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char
  rts

; Convert number in A to BCD
; Returns: A = tens, temp = ones
convert_bcd:
  ldx #0
div10:
  cmp #10
  bcc div10_done
  sec
  sbc #10
  inx
  jmp div10
div10_done:
  sta temp
  txa
  rts

; LCD functions
lcd_wait:
  pha
  lda #%00000000  ; PORTB = input
  sta DDRB
lcd_busy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000
  bne lcd_busy

  lda #RW
  sta PORTA
  lda #%11111111  ; PORTB = output
  sta DDRB
  pla
  rts

lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0          ; Clear RS/RW/E
  sta PORTA
  lda #E          ; Set E
  sta PORTA
  lda #0          ; Clear E
  sta PORTA
  rts

lcd_char:
  jsr lcd_wait
  sta PORTB
  lda #RS         ; Set RS
  sta PORTA
  lda #(RS | E)   ; Set E
  sta PORTA
  lda #RS         ; Clear E
  sta PORTA
  rts

; Interrupt handler - only handles CB1 for SELECT button
irq:
  pha
  
  ; Check for CB1 interrupt
  lda IFR
  and #%00010000  ; Check CB1 bit (bit 4)
  beq irq_done
  
  ; Clear CB1 interrupt flag
  lda #%00010000  ; Clear CB1 bit
  sta IFR
  
  ; Increment minutes on SELECT press
  inc time_m
  jsr check_minute_rollover

irq_done:
  pla
  rti

  .org $fffc
  .word reset
  .word irq       ; Point to our interrupt handler
